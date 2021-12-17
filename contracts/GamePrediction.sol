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
        address token;
    }
    
    struct Order {
        uint128 round;
        uint number;
        uint amount;
        address user;
    }

    Round[] rounds;
    mapping(uint128 => uint) public round2claimedAmount;
    mapping(uint128 => mapping(address => bool)) public round2user2cliamed;
    mapping(uint128 => mapping(uint => uint)) public round2number2totalAmount;    
    mapping(address => mapping(uint128 => Order[])) public user2round2orders;    

    uint public rate;
    address public rewardPool;
    
    event SetRewardPool(address user, address oldOne, address newOne);
    event SetRate(address user, uint oldOne, uint newOne);
    event AddRound(address user, uint128 roundId, uint128 maxNumber, uint startTime, uint endTime, address token);
    event UpdateRound(address user, uint128 roundId, uint128 maxNumber, uint startTime, uint endTime);
    event SetWinNumber(address user, uint128 roundId, uint128 winNumber);
    event Predict(address user, uint128 roundId, uint128 num, uint amount);
    event Claim(address caller, address indexed user, uint128 roundId, uint amount);

    receive() external payable {
    }
    
    function initialize(uint _rate, address _rewardPool) external initializer {
        require(_rewardPool != address(0), 'GamePrediction: INVALID_ADDR');
        owner = msg.sender;
        rate = _rate;
        rewardPool = _rewardPool;
        rounds.push(Round({maxNumber: 0, winNumber: 0, startTime: 0, endTime: 0, totalAmount: 0, accAmount: 0, token: address(0)}));
    }

    function setRewardPool(address _rewardPool) external onlyAdmin {
        require(_rewardPool != address(0) && _rewardPool != rewardPool, "GamePrediction: INVALID_POOL_ADDR");
        emit SetRewardPool(msg.sender, rewardPool, _rewardPool);
        rewardPool = _rewardPool;
    }

    function setRate(uint _rate) external onlyAdmin {
        require(_rate != rate, "GamePrediction: INVALID_RATE");
        emit SetRate(msg.sender, rate, _rate);
        rate = _rate;
    }

    function addRound(uint128 _maxNumber, uint _startTime, uint _endTime, address _token) external onlyAdmin returns (uint128 roundId) {
        require(_maxNumber > 0, 'GamePrediction: INVALID_MAX_NUM');
        require(_startTime < _endTime && block.timestamp < _endTime, 'GamePrediction: INVALID_TIME');
        roundId = uint128(rounds.length);
        rounds.push(Round({maxNumber: _maxNumber, winNumber: 0, startTime: _startTime, endTime: _endTime, totalAmount: 0, accAmount: 0, token: _token}));
        emit AddRound(msg.sender, roundId, _maxNumber, _startTime, _endTime, _token);
    }

    function updateRound(uint128 _roundId, uint128 _maxNumber, uint _startTime, uint _endTime) external onlyAdmin {
        require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        Round storage round = rounds[uint(_roundId)];
        require(_maxNumber > round.maxNumber, 'GamePrediction: INVALID_MAX_NUM');
        require(block.timestamp < round.endTime, 'GamePrediction: ROUND_EXPIRED');
        round.maxNumber = _maxNumber;
        if (block.timestamp < round.startTime) {
            round.startTime = _startTime;
        }
        round.endTime = _endTime;
        emit UpdateRound(msg.sender, _roundId, round.maxNumber, round.startTime, round.endTime);
    }

    function getRound(uint128 _roundId) external view returns (Round memory round) {
        require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        round = rounds[_roundId];
    }

    function setWinNumber(uint128 _roundId, uint128 _winNumber) external onlyAdmin {
        require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        require(_winNumber <= rounds[_roundId].maxNumber && _winNumber > 0 , 'GamePrediction: INVALID_WIN_NUMBER');
        require(block.timestamp > rounds[_roundId].endTime, 'GamePrediction: ROUND_NOT_FINISHED');
        rounds[_roundId].winNumber = _winNumber;
        rounds[_roundId].accAmount = rounds[_roundId].totalAmount.div(round2number2totalAmount[_roundId][_winNumber]);
        if (round2number2totalAmount[_roundId][_winNumber] == 0) {
            if (rounds[_roundId].token == address(0)) {
                TransferHelper.safeTransferETH(rewardPool, rounds[_roundId].totalAmount);
            } else {
                TransferHelper.safeTransfer(rounds[_roundId].token, rewardPool, rounds[_roundId].totalAmount);
            }
            round2claimedAmount[_roundId] = rounds[_roundId].totalAmount;
        }
        emit SetWinNumber(msg.sender, _roundId, _winNumber);    
    }

    function predict(uint128 _roundId, uint128 _num, uint _amount) external payable {
        require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        Round storage round = rounds[uint(_roundId)];
        require(_num > 0 && _num <= round.maxNumber, 'GamePrediction: INVALID_NUM');
        require(block.timestamp >= round.startTime && block.timestamp < round.endTime, 'GamePrediction: WRONG_TIME');
        require(_amount > 0, 'GamePrediction: INVALID_AMOUNT');

        // transfer token
        if (round.token == address(0)) {
            require(_amount == msg.value, 'GamePrediction: INVALID_AMOUNT');
        } else {
            TransferHelper.safeTransferFrom(round.token, msg.sender, address(this), _amount);
        }

        // udpate order info
        round.totalAmount = round.totalAmount.add(_amount);
        round2number2totalAmount[_roundId][_num] = round2number2totalAmount[_roundId][_num].add(_amount);
        (bool flag, uint index) = _userNumOrder(_roundId, _num, msg.sender);
        if (!flag) {
            user2round2orders[msg.sender][_roundId].push(Order({round: _roundId, number: _num, amount: _amount, user: msg.sender}));
        } else {
            user2round2orders[msg.sender][_roundId][index].amount = user2round2orders[msg.sender][_roundId][index].amount.add(_amount);
        }

        emit Predict(msg.sender, _roundId, _num, _amount);
    }

    function getUserOrderlength(uint128 _roundId, address _user) public view returns(uint) {
        require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        return user2round2orders[_user][_roundId].length;
    }

    function getUserOrder(uint128 _roundId, address _user, uint _orderId) public view returns(Order memory order) {
        require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        return user2round2orders[_user][_roundId][_orderId];
    }

    function getAllUserOrders(uint128 _roundId, address _user) external view returns(Order[] memory orders) {
        require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        uint length = getUserOrderlength(_roundId, _user);
        if (length == 0) return orders;
        orders = new Order[](length);
        for (uint i = 0; i < length; i++) {
            orders[i] = getUserOrder(_roundId, _user, i);
        }
    }

    function getReward(uint128 _roundId, address _user) public view returns (uint rewardAmount) {
        require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        Round memory round = rounds[_roundId];
        if (round.endTime > block.timestamp || round.winNumber == 0) return rewardAmount;
        (bool flag, uint index) = _userNumOrder(_roundId, round.winNumber, _user);
        if (!flag) return rewardAmount;
        rewardAmount = user2round2orders[_user][_roundId][index].amount.mul(round.accAmount);
        rewardAmount = round.totalAmount.sub(round2claimedAmount[_roundId]) >= rewardAmount ? rewardAmount: round.totalAmount.sub(round2claimedAmount[_roundId]);
    } 

    function claim(uint128 _roundId, address _user) external {
        require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        uint rewardAmount = getReward(_roundId, _user);
        require(rewardAmount > 0, 'GmaePrediction: REWARDAMOUNT_ZERO');
        require(!round2user2cliamed[_roundId][_user], "GamePrediction: REWARD_CLAIMED");
        Round memory round = rounds[_roundId];
        uint fee = rewardAmount.mul(rate).div(1e18);
        if (round.token == address(0)) {
            if (fee != 0) TransferHelper.safeTransferETH(team(), fee);
            TransferHelper.safeTransferETH(_user, rewardAmount.sub(fee));
        } else {
            if (fee != 0) TransferHelper.safeTransfer(round.token, team(), fee);
            TransferHelper.safeTransfer(round.token, _user, rewardAmount);
        }
        round2claimedAmount[_roundId] = round2claimedAmount[_roundId].add(rewardAmount);
        round2user2cliamed[_roundId][_user] = true;
        emit Claim(msg.sender, _user, _roundId, rewardAmount.sub(fee));
    }

    function getUserOrderNumber(uint128 _roundId, uint128 _num, address _user) external view returns (uint) {
         require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        (bool flag, uint index) = _userNumOrder(_roundId, _num, _user);
        if (!flag) return 0;
        return user2round2orders[_user][_roundId][index].amount;
    }

    function getNumbersAmount(uint128 _roundId, uint128[] memory _nums) external view returns (uint[] memory amounts) {
         require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
         if (_nums.length == 0) return amounts;
         amounts = new uint[](_nums.length);
         for (uint i = 0; i < _nums.length; i++) {
             amounts[i] = round2number2totalAmount[_roundId][_nums[i]];
         }
    }

    function _userNumOrder(uint128 _roundId, uint128 _num, address _user) internal view returns (bool flag, uint index) {
        for (uint i = 0; i < user2round2orders[_user][_roundId].length; i++) {
            if (user2round2orders[_user][_roundId][i].number == _num) {
                flag = true;
                index = i;
            }
        }
    }
}