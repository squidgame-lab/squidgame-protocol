// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IPancakeRouter.sol';
import './interfaces/IPancakeFactory.sol';
import './interfaces/IPancakePair.sol';
import './interfaces/IGameTicket.sol';
import './libraries/TransferHelper.sol';
import './modules/ReentrancyGuard.sol';
import './modules/Configable.sol';
import './modules/Initializable.sol';

import 'hardhat/console.sol';

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract GameTicketExchange is Configable, ReentrancyGuard, Initializable {
    using SafeMath for uint;

    address public weth;
    address public pancakeRouter;
    mapping(uint => address) public levelTickets;
    mapping(address => bool) public paymentTokenWhiteList;
    
    event SetLevelTicket(address indexed _user, uint level, address ticket);
    event SetPTW(address indexed _user, address paymentToken, bool status);
    event Bought(address indexed user, uint ticketAmount, address paymentToken, uint paymentTokenAmount);

    receive() external payable {
    }

    modifier OnlyExistLevel(uint _level) {
        require(levelTickets[_level] != address(0), 'GameTicketExchange: LEVEL_NOT_EXIST');
        _;
    }
 
    function initialize(address _weth, address _pancakeRouter) external initializer {
        require(_weth != address(0), 'GameTicketExchange: INVALID_WETH_ADDR');
        require(_pancakeRouter != address(0), 'GameTicketExchange: INVALID_ROUTER_ADDR');
        owner = msg.sender;
        weth = _weth;
        pancakeRouter = _pancakeRouter;
    }

    function setLevelTicket(uint _level, address _ticket) public onlyAdmin {
        require(_level != 0, 'GameTicketExchange: INVALID_LEVEL');
        require(_ticket != address(0), 'GameTicketExchange: INVALID_TICKET_ADDR');
        levelTickets[_level] = _ticket;
        emit SetLevelTicket(msg.sender, _level, _ticket);
    }

    function batchSetLevelTicket(uint[] memory _levels, address[] memory _tickets) external onlyAdmin {
        require(_levels.length == _tickets.length, 'GameTicketExchange: INVALID_ARGS_LENGTH');
        for (uint i = 0; i < _levels.length; i++) {
            setLevelTicket(_levels[i], _tickets[i]);
        }
    }

    function setPTW(address _paymentToken, bool _status) public onlyAdmin {
        paymentTokenWhiteList[_paymentToken] = _status;
        emit SetPTW(msg.sender, _paymentToken, _status);
    }

    function batchSetPTW(address[] memory _paymentTokens, bool[] memory _status) external onlyAdmin {
        require(_paymentTokens.length == _status.length, 'GameTicketExchange: INVALID_ARGS_LENGTH');
        for (uint i = 0; i < _paymentTokens.length; i++) {
            setPTW(_paymentTokens[i], _status[i]);
        }
    }

    function getStatus(uint _level, address _user) public view OnlyExistLevel(_level) returns (bool) {
        if (_level == 1) return true;
        return IGameTicket(levelTickets[_level]).status(_user);
    }

    function getTicketsAmount(uint _level, address _user) public view OnlyExistLevel(_level) returns (uint) {
        return IGameTicket(levelTickets[_level]).tickets(_user);
    }

    struct TicketInfo {
        address buyToken;
        uint unit;
        address gameToken;
        uint gameTokenUnit;
    }

    function getTicketInfo(uint _level) public view returns (TicketInfo memory ticketInfo){
        address gameToken;
        uint gameTokenUnit;
        if (_level != 1) {
            gameToken = IGameTicket(levelTickets[_level]).gameToken();
            gameTokenUnit = IGameTicket(levelTickets[_level]).gameTokenUnit();
        }
        ticketInfo = TicketInfo({
            buyToken: IGameTicket(levelTickets[_level]).buyToken(),
            unit: IGameTicket(levelTickets[_level]).unit(),
            gameToken: gameToken,
            gameTokenUnit: gameTokenUnit
        });
    }

    function getPaymentAmount(uint _level, uint _ticketAmount, address _paymentToken) public view OnlyExistLevel(_level) returns (uint) {
        require(paymentTokenWhiteList[_paymentToken], 'GameTicketExchange: NOT_SUPPORT_PAYMENT_TOKEN');
        TicketInfo memory ticketInfo = getTicketInfo(_level);
        (uint buyTokenAmount, ,uint convertAmount) = _getLevelTokenAmount(ticketInfo, _ticketAmount);
        if (_paymentToken == ticketInfo.buyToken) return buyTokenAmount.add(convertAmount);
        if (_paymentToken == address(0)) {
            return _calculateAmountIn(buyTokenAmount.add(convertAmount), weth, ticketInfo.buyToken);
        } else {
            return _calculateAmountIn(buyTokenAmount.add(convertAmount), _paymentToken, ticketInfo.buyToken);
        }
    }

    function buy(
        uint _level,
        uint _ticketAmount,
        address _paymentToken,
        uint _paymentTokenAmount,
        uint deadline
    ) external payable OnlyExistLevel(_level) {
        require(paymentTokenWhiteList[_paymentToken], 'GameTicketExchange: NOT_SUPPORT_PAYMENT_TOKEN');
        uint paymentTokenAmount = getPaymentAmount(_level, _ticketAmount, _paymentToken);
        require(_paymentTokenAmount >= paymentTokenAmount, 'GameTicketExchange: NOT_ENOUGH_PAYMENT');

        if (_paymentToken == address(0)) {
            require(paymentTokenAmount <= msg.value, 'GameTicketExchange: INVALID_VALUE');
            IWETH(weth).deposit{value: msg.value}();
        } else {
            TransferHelper.safeTransferFrom(_paymentToken, msg.sender, address(this), paymentTokenAmount);
        }

        TicketInfo memory ticketInfo = getTicketInfo(_level);
        (uint buyTokenAmount, uint gameTokenAmount, uint convertAmount) = _getLevelTokenAmount(ticketInfo, _ticketAmount);
        address[] memory path = new address[](2);
        if (_paymentToken != ticketInfo.buyToken) {
            path[0] = _paymentToken != address(0)? _paymentToken: weth;
            IERC20(path[0]).approve(pancakeRouter, paymentTokenAmount);
            path[1] = ticketInfo.buyToken;
            IPancakeRouter(pancakeRouter).swapTokensForExactTokens(
                buyTokenAmount.add(convertAmount),
                paymentTokenAmount,
                path,
                address(this),
                deadline
            );
        }
        IERC20(ticketInfo.buyToken).approve(levelTickets[_level], buyTokenAmount);
        if (gameTokenAmount != 0) {
            path[0] = ticketInfo.buyToken;
            IERC20(ticketInfo.buyToken).approve(pancakeRouter, convertAmount);
            path[1] = ticketInfo.gameToken;
            IPancakeRouter(pancakeRouter).swapTokensForExactTokens(
                gameTokenAmount,
                convertAmount,
                path,
                address(this),
                deadline
            );
            IERC20(ticketInfo.gameToken).approve(levelTickets[_level], gameTokenAmount);
        }

        IGameTicket(levelTickets[_level]).buy(buyTokenAmount, msg.sender);
        emit Bought(msg.sender, _ticketAmount, _paymentToken, paymentTokenAmount);
    }

    function _getLevelTokenAmount(TicketInfo memory ticketInfo, uint _ticketAmount) internal view returns (uint buyTokenAmount, uint gameTokenAmount, uint convertAmount) {
        if (ticketInfo.unit != 0) {
            buyTokenAmount = _ticketAmount.mul(ticketInfo.unit);
        }
        if (ticketInfo.gameTokenUnit != 0 && ticketInfo.gameToken != address(0)) {
            gameTokenAmount = _ticketAmount.mul(ticketInfo.gameTokenUnit);
            convertAmount = _calculateAmountIn(gameTokenAmount, ticketInfo.buyToken, ticketInfo.gameToken);
        }
    }

    function _calculateAmountIn(uint amountB, address tokenA, address tokenB) internal view returns (uint amountA) {
        if (tokenA == tokenB) return amountB;
        address factory = IPancakeRouter(pancakeRouter).factory();
        address pair = IPancakeFactory(factory).getPair(tokenA, tokenB);
        (uint112 reserver0, uint112 reserver1, ) = IPancakePair(pair).getReserves();
        if (tokenA > tokenB) (reserver0, reserver1) = (reserver1, reserver0);
        amountA = IPancakeRouter(pancakeRouter).getAmountIn(amountB, reserver0, reserver1);
    }
}
