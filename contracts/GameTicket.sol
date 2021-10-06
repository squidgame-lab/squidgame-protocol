// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './libraries/TransferHelper.sol';
import './modules/ReentrancyGuard.sol';
import './modules/Pausable.sol';
import './modules/Configable.sol';
import './modules/Initializable.sol';
import './interfaces/IRewardSource.sol';

contract GameTicket is IRewardSource, Configable, Pausable, ReentrancyGuard, Initializable {
    using SafeMath for uint;
    address public override buyToken;
    address public rewardPool;
    uint public feeRate;
    uint public unit;
    uint public total;
    mapping(address => uint) public override tickets;
 
    event FeeRateChanged(uint indexed _old, uint indexed _new);
    event RewardPoolChanged(address indexed _old, address indexed _new);
    event Bought(address indexed from, address indexed to, uint indexed value);
    
    receive() external payable {
    }

    function initialize(address _buyToken, uint _unit) external initializer {
        require(_buyToken != address(0), 'GameTicket: ZERO_ADDRESS');
        owner = msg.sender;
        buyToken = _buyToken;
        unit = _unit;
    }

    function setUnit(uint _unit) external onlyAdmin {
        require(_unit != unit, 'GameTicket: NO_CHANGE');
        unit = _unit;
    }

    function setFeeRate(uint _rate) external onlyAdmin {
        require(_rate != feeRate, 'GameTicket: NO_CHANGE');
        emit FeeRateChanged(feeRate, _rate);
        feeRate = _rate;
    }

    function setRewardPool(address _pool) external onlyDev {
        require(_pool != rewardPool, 'GameTicket: NO_CHANGE');
        emit RewardPoolChanged(rewardPool, _pool);
        rewardPool = _pool;
    }

    function buy(uint _value, address _to) external payable nonReentrant whenNotPaused returns (bool) {
        require(_value > 0, 'GameTicket: ZERO');
        require(_value % unit == 0, 'GameTicket: REMAINDER');
        if (buyToken == address(0)) {
            require(_value == msg.value, 'GameTicket: INVALID_VALUE');
        } else {
            require(IERC20(buyToken).balanceOf(msg.sender) >= _value, 'GameTicket: INSUFFICIENT_BALANCE');
            TransferHelper.safeTransferFrom(buyToken, msg.sender, address(this), _value);
        }

        tickets[_to] = tickets[_to].add(_value);
        total = total.add(_value);
        emit Bought(msg.sender, _to, _value);
        return true;
    }

    function withdraw(uint _value) external virtual override nonReentrant whenNotPaused returns (uint reward, uint fee) {
        require(msg.sender == rewardPool, 'GameTicket: FORBIDDEN');
        require(_value > 0, 'GameTicket: ZERO');
        require(getBalance() >= _value, 'GameTicket: INSUFFICIENT_BALANCE');

        reward = _value;
        if(feeRate > 0) {
            fee = _value.div(feeRate);
            reward = _value.sub(fee);
        }
        if (buyToken == address(0)) {
            if(fee > 0) TransferHelper.safeTransferETH(team(), fee);
            if(reward > 0) TransferHelper.safeTransferETH(rewardPool, reward);
        } else {
            if(fee > 0) TransferHelper.safeTransfer(buyToken, team(), fee);
            if(reward > 0) TransferHelper.safeTransfer(buyToken, rewardPool, reward);
        }
        emit Withdrawed(rewardPool, reward, team(), fee);
    }

    function getBalance() public view virtual override returns (uint) {
        uint balance = address(this).balance;
        if(buyToken != address(0)) {
            balance = IERC20(buyToken).balanceOf(address(this));
        }
        return balance;
    }
}
