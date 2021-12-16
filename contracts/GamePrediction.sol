// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './libraries/TransferHelper.sol';
import './modules/ReentrancyGuard.sol';
import './modules/Configable.sol';
import './modules/Initializable.sol';
import './interfaces/IRewardSource.sol';

contract GamePrediction is Configable, ReentrancyGuard, Initializable {
    using SafeMath for uint;
    using SafeMath for uint128;

    struct Round {
        uint128 maxNumber;
        uint128 winNumber;
        uint startTime;
        uint endTime;
        uint totalAmount;
        uint accAmount;
    }
    
    struct Order {
        uint128 round;
        uint number;
        uint amount;
        address user;
    }

    Round[] rounds;
    mapping(uint128 => mapping(uint => uint)) round2number2totalAmoun;    
    mapping(address => mapping(uint128 => Order[])) user2round2orders;

    uint public rate;
    address public token;
    
    function initialize(address _token, uint _rate) external initializer {
        require(_token != address(0), 'GamePrediction: INVALID_TOKEN_ADDR');
        owner = msg.sender;
        token = _token;
        rate = _rate;
        rounds.push({maxNumber: 0, winNumber: 0, startTime: 0, endTime: 0, totalAmount: 0, accAmount: 0});
    }

    function addRound(uint128 _maxNumber, uint _startTime, uint _endTime) external onlyAdmin returns (uint128 roundId) {
        return 0;
    }

    function updateRound(uint128 _roundId, uint128 _maxNumber, uint _startTime, uint _endTime) external onlyAdmin {

    }

    function setWinNumber(uint128 _roundId, uint128 _winNumber) external onlyAdmin {

    }

    function predict(uint128 _roundId, uint _amount) external {

    }

    function getReward(uint128 _roundId) public view returns (uint) {

    } 

    function claim(uint128 _roundId) external {

    }
}