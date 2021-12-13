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

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract GameTicketExchange is Configable, ReentrancyGuard, Initializable {
    using SafeMath for uint;

    address public weth;
    address public pancakeRouter;
    mapping(uint => address) levelTickets;
    
    event SetLevelTicket(address indexed _user, uint level, address ticket);
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

    function getStatus(uint _level) public view OnlyExistLevel(_level) returns (bool) {
        if (_level == 1) return true;
        return IGameTicket(levelTickets[_level]).status(msg.sender);
    }

    function getTicketBalance(uint _level) public view OnlyExistLevel(_level) returns (uint) {
        return IGameTicket(levelTickets[_level]).tickets(msg.sender);
    }

    function getPaymentAmount(uint _level, uint _ticketAmount, address _paymentToken) public view OnlyExistLevel(_level) returns (uint) {
        TicketInfo memory ticketInfo = _getTicketInfo(_level);
        (uint buyTokenAmount, , ) = _getLevelTokenAmount(ticketInfo, _ticketAmount);
        if (_paymentToken == address(0)) {
            return _calculateAmountIn(buyTokenAmount, weth, ticketInfo.buyToken);
        } else {
            return _calculateAmountIn(buyTokenAmount, _paymentToken, ticketInfo.buyToken);
        }
    }

    function buy(uint _level, uint _ticketAmount, address _paymentToken, uint deadline) external payable OnlyExistLevel(_level) {
        uint paymentTokenAmount = getPaymentAmount(_level, _ticketAmount, _paymentToken);
        if (_paymentToken == address(0)) {
            require(paymentTokenAmount <= msg.value, 'GameTicketExchange: INVALID_VALUE');
            IWETH(weth).deposit{value: msg.value}();
        } else {
            TransferHelper.safeTransferFrom(_paymentToken, msg.sender, address(this), paymentTokenAmount);
        }

        TicketInfo memory ticketInfo = _getTicketInfo(_level);
        (uint buyTokenAmount, uint gameTokenAmount, uint convertAmount) = _getLevelTokenAmount(ticketInfo, _ticketAmount);
        address[] memory path;
        if (_paymentToken != ticketInfo.buyToken) {
            IERC20(_paymentToken).approve(pancakeRouter, paymentTokenAmount);
            path[0] = _paymentToken;
            path[1] = ticketInfo.buyToken;
            IPancakeRouter(pancakeRouter).swapTokensForExactTokens(
                buyTokenAmount,
                paymentTokenAmount,
                path,
                address(this),
                deadline
            );
        }
        if (gameTokenAmount != 0) {
            IERC20(ticketInfo.buyToken).approve(pancakeRouter, convertAmount);
            path[0] = ticketInfo.buyToken;
            path[1] = ticketInfo.gameToken;
            IPancakeRouter(pancakeRouter).swapTokensForExactTokens(
                gameTokenAmount,
                convertAmount,
                path,
                address(this),
                deadline
            );
        }

        IGameTicket(levelTickets[_level]).buy(buyTokenAmount.sub(convertAmount), msg.sender);
        emit Bought(msg.sender, _ticketAmount, _paymentToken, paymentTokenAmount);
    }

    struct TicketInfo {
        address buyToken;
        uint uintAmount;
        address gameToken;
        uint gameTokenUint;
    }

    function _getTicketInfo(uint _level) internal view returns (TicketInfo memory ticketInfo){
        ticketInfo = TicketInfo({
            buyToken: IGameTicket(levelTickets[_level]).buyToken(),
            uintAmount: IGameTicket(levelTickets[_level]).unit(),
            gameToken: IGameTicket(levelTickets[_level]).gameToken(),
            gameTokenUint: IGameTicket(levelTickets[_level]).gameTokenUnit()
        });
    }

    function _getLevelTokenAmount(TicketInfo memory ticketInfo, uint _ticketAmount) internal view returns (uint buyTokenAmount, uint gameTokenAmount, uint convertAmount) {
        if (ticketInfo.uintAmount != 0) {
            buyTokenAmount = _ticketAmount.mul(ticketInfo.uintAmount);
        }
        if (ticketInfo.gameTokenUint != 0) {
            gameTokenAmount = _ticketAmount.mul(ticketInfo.gameTokenUint);
            convertAmount = _calculateAmountIn(gameTokenAmount, ticketInfo.buyToken, ticketInfo.gameToken);
            buyTokenAmount = buyTokenAmount.add(convertAmount);
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
