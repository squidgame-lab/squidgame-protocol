 // SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import './interfaces/IERC20.sol';
import './libraries/SafeMath.sol';
import './libraries/TransferHelper.sol';
import './modules/ReentrancyGuard.sol';
import './modules/Configable.sol';
import './modules/Initializable.sol';

import 'hardhat/console.sol';

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
        uint128 orderId;
        uint128 round;
        uint number;
        uint amount;
        address user;
    }

    Round[] rounds;
    Order[] orders;
    mapping(uint128 => uint) public round2claimedAmount;
    mapping(uint128 => mapping(address => bool)) public round2user2cliamed;
    mapping(uint128 => mapping(uint => uint)) public round2number2totalAmount;
    mapping(uint128 => uint128[]) public round2orders;
    mapping(address => uint128[]) public user2orders;   
    mapping(address => mapping(uint128 => uint128[])) public user2round2orders;  

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
        orders.push(Order({orderId: 0, round: 0, number: 0, amount: 0, user: address(0)}));
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
        if (round2number2totalAmount[_roundId][_winNumber] == 0) {
            if (rounds[_roundId].token == address(0)) {
                TransferHelper.safeTransferETH(rewardPool, rounds[_roundId].totalAmount);
            } else {
                TransferHelper.safeTransfer(rounds[_roundId].token, rewardPool, rounds[_roundId].totalAmount);
            }
            round2claimedAmount[_roundId] = rounds[_roundId].totalAmount;
        } else {
            rounds[_roundId].accAmount = rounds[_roundId].totalAmount.mul(1e18).div(round2number2totalAmount[_roundId][_winNumber]);
        }
        rounds[_roundId].winNumber = _winNumber;
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
            uint128 orderId = uint128(orders.length);
            orders.push(Order({orderId: orderId, round: _roundId, number: _num, amount: _amount, user: msg.sender}));
            user2round2orders[msg.sender][_roundId].push(orderId);
            user2orders[msg.sender].push(orderId);
            round2orders[_roundId].push(orderId);
        } else {
            orders[index].amount = orders[index].amount.add(_amount);
        }

        emit Predict(msg.sender, _roundId, _num, _amount);
    }

    function getUserRoundOrdersLength(uint128 _roundId, address _user) public view returns(uint) {
        require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        return user2round2orders[_user][_roundId].length;
    }

    function getUserOrdersLength(address _user) public view returns(uint) {
        return user2orders[_user].length;
    }

    function getUserRoundOrders(uint128 _roundId, address _user, uint _startIndex, uint _endIndex) public view returns(Order[] memory userOrders) {
        require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        require(_startIndex >= _endIndex && _startIndex < getUserRoundOrdersLength(_roundId, _user), 'GamePrediction: INVALID_INDEX');
        uint ordersLength = _startIndex.sub(_endIndex).add(1);
        userOrders = new Order[](ordersLength);
        for (uint i = 0; i < ordersLength; i++) {
            uint128 orderId = user2round2orders[_user][_roundId][_startIndex.sub(i)];
            userOrders[i] = orders[orderId];
        }
    }

    function getUserOrders(address _user, uint _startIndex, uint _endIndex) external view returns(Order[] memory userOrders) {
        require(_startIndex >= _endIndex && _startIndex < getUserOrdersLength(_user), 'GamePrediction: INVALID_INDEX');
        uint ordersLength = _startIndex.sub(_endIndex).add(1);
        userOrders = new Order[](ordersLength);
        for (uint i = 0; i < ordersLength; i++) {
            uint128 orderId = user2orders[_user][_startIndex.sub(i)];
            userOrders[i] = orders[orderId];
        }
    }

    function getUserNumberOrder(uint128 _roundId, uint128 _num, address _user) external view returns (Order memory order) {
         require(_roundId < rounds.length, 'GamePrediction: INVALID_ROUNDID');
        (bool flag, uint index) = _userNumOrder(_roundId, _num, _user);
        if (!flag) return order;
        order = orders[index];
    }

    function getReward(uint128 _orderId, address _user) public view returns (uint rewardAmount) {
        require(_orderId < orders.length, 'GamePrediction: INVALID_ORDERID');
        Order memory order = orders[_orderId];
        Round memory round = rounds[order.round];
        if (round.endTime > block.timestamp || round.winNumber == 0) return rewardAmount;
        if (order.number != round.winNumber || order.user != _user) return rewardAmount;
        rewardAmount = order.amount.mul(round.accAmount).div(1e18);
        rewardAmount = round.totalAmount.sub(round2claimedAmount[order.round]) >= rewardAmount ? rewardAmount: round.totalAmount.sub(round2claimedAmount[order.round]);
    } 

    function claim(uint128 _orderId, address _user) external {
        require(_orderId < orders.length, 'GamePrediction: INVALID_ORDERID');
        Order memory order = orders[_orderId];
        uint rewardAmount = getReward(_orderId, _user);
        require(rewardAmount > 0, 'GmaePrediction: REWARDAMOUNT_ZERO');
        require(!round2user2cliamed[order.round][_user], "GamePrediction: REWARD_CLAIMED");
        Round memory round = rounds[order.round];
        uint fee = rewardAmount.mul(rate).div(1e18);
        if (round.token == address(0)) {
            if (fee != 0) TransferHelper.safeTransferETH(team(), fee);
            TransferHelper.safeTransferETH(_user, rewardAmount.sub(fee));
        } else {
            if (fee != 0) TransferHelper.safeTransfer(round.token, team(), fee);
            TransferHelper.safeTransfer(round.token, _user, rewardAmount.sub(fee));
        }
        round2claimedAmount[order.round] = round2claimedAmount[order.round].add(rewardAmount);
        round2user2cliamed[order.round][_user] = true;
        emit Claim(msg.sender, _user, order.round, rewardAmount.sub(fee));
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
            uint128 orderId = user2round2orders[_user][_roundId][i];
            if (orders[orderId].number == _num) {
                flag = true;
                index = orderId;
            }
        }
    }
}