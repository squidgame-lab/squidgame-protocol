// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;
pragma experimental ABIEncoderV2;

import "./libraries/SafeMath128.sol";
import './libraries/TransferHelper.sol';
import './modules/ReentrancyGuard.sol';
import './modules/Pausable.sol';
import './modules/Configable.sol';
import './modules/Initializable.sol';
import './interfaces/IERC20.sol';
import './interfaces/IRewardSource.sol';
import './interfaces/IShareToken.sol';

contract GamePoolActivity is IRewardSource, Configable, Pausable, ReentrancyGuard, Initializable {
    using SafeMath128 for uint128;
    address public rewardSource;
    address public override buyToken;
    address public shareToken;
    address public nextPool;
    uint64 public epoch;
    uint64 public totalRound;
    uint64 public shareReleaseEpoch; // block number
    mapping(address => uint) public override tickets;
    bool public isFromTicket;
    uint16 public userMaxScore;
    
    struct PlayData {
        address user;
        uint128 ticketAmount;
        uint16 score;
        uint16 score1;
        uint16 score2;
        uint16 score3;
    }
    
    struct RoundData {
        uint128 ticketTotal;
        uint128 rewardTotal;
        uint128 strategySn;
        uint64 startTime;
        uint64 releaseBlockStart;
        uint64 releaseBlockEnd;
    }

    struct Order {
        address user;
        uint64 roundNumber;
        uint128 ticketAmount;
        uint128 claimedShareAmount;
        uint16 score;
        uint16 score1;
        uint16 score2;
        uint16 score3;
    }

    struct OrderResult {
        address user;
        uint128 orderId;
        uint64 roundNumber;
        uint64 startTime;
        uint128 ticketAmount;
        uint16 score;
        uint16 score1;
        uint16 score2;
        uint16 score3;
        uint128 claimShareAmount;
        uint128 claimedShareAmount;
        uint128 claimShareAvaliable;
    }

    struct Rate {
        uint128 score;
        uint128 score1;
        uint128 score2;
        uint128 score3;
    }

    Order[] public orders;
    uint128 public totalStrategy;
    mapping (uint128 => Rate) public strategies;
    mapping (uint64 => RoundData) public historys;
    mapping (address => uint128[]) public userOrders;
    mapping (uint128 => uint128[]) public roundOrders;
    mapping (address => mapping (uint128 => uint128)) public userRoundOrderMap;
    bool public enableRoundOrder;
    uint128 public feeRate;
    uint128 public ticketTotal;
    uint128 public buyTokenUnit;

    event NewRound(uint128 indexed value);
    event Claimed(address indexed user, uint128 indexed orderId, uint128 winAmount, uint128 shareAmount);
    event FeeRateChanged(uint indexed _old, uint indexed _new);

    receive() external payable {
    }
 
    function initialize() external initializer {
        owner = msg.sender;
    }

    function configure(address _rewardSource, address _shareToken, address _nextPool, uint64 _epoch, uint64 _shareReleaseEpoch, bool _isFromTicket, bool _enableRoundOrder) external onlyDev {
        rewardSource = _rewardSource;
        buyToken = IRewardSource(_rewardSource).buyToken();
        shareToken = _shareToken;
        nextPool = _nextPool;
        epoch = _epoch;
        shareReleaseEpoch = _shareReleaseEpoch;
        isFromTicket = _isFromTicket;
        enableRoundOrder = _enableRoundOrder;

        if(buyToken == address(0)) {
            buyTokenUnit = uint128(10**18);
        } else {
            buyTokenUnit = uint128(10** uint(IERC20(buyToken).decimals()));
        }
    }

    function setFeeRate(uint128 _rate) external onlyManager {
        require(_rate != feeRate, 'no change');
        require(_rate <= 10000, 'invalid param');
        emit FeeRateChanged(feeRate, _rate);
        feeRate = _rate;
    }

    function setUserMaxScore(uint16 _userMaxScore) external onlyDev {
        require(userMaxScore != _userMaxScore, 'no change');
        require(_userMaxScore <= 10000, 'invalid param');
        userMaxScore = _userMaxScore;
    }

    function setRate(Rate memory _values) external onlyManager {
        totalStrategy++;
        strategies[totalStrategy] = _values;
    }

    function uploadOne(PlayData memory data) public onlyUploader {
        uint16 _total = data.score + data.score1 + data.score2 + data.score3;
        uint128 _totalScore = uint128(_total) * buyTokenUnit;
        require(_total <= userMaxScore, 'score overflow');
        require(_totalScore <= data.ticketAmount, 'score over ticket');
        uint128 orderId = userRoundOrderMap[data.user][totalRound];
        bool exist;
        if(orderId > 0 || (orderId == 0 && totalRound == 0 && userOrders[data.user].length > 0)) {
            exist = true;
        }

        if(!exist) {
            if(isFromTicket) {
                require(tickets[data.user] + data.ticketAmount <= IRewardSource(rewardSource).tickets(data.user), 'ticket overflow');
            }
            ticketTotal = ticketTotal.add(data.ticketAmount);
            orderId = uint128(orders.length);
            userRoundOrderMap[data.user][totalRound] = orderId;
            if(userOrders[data.user].length == 0) {
                userOrders[data.user] = new uint128[](1);
                userOrders[data.user][0] = orderId;
            } else {
                userOrders[data.user].push(orderId);
            }

            if(enableRoundOrder) {
                if(roundOrders[totalRound].length == 0) {
                    roundOrders[totalRound] = new uint128[](1);
                    roundOrders[totalRound][0] = orderId;
                } else {
                    roundOrders[totalRound].push(orderId);
                }
            }

            orders.push(Order({
                roundNumber: totalRound,
                user: data.user,
                ticketAmount: data.ticketAmount,
                claimedShareAmount: 0,
                score: data.score,
                score1: data.score1,
                score2: data.score2,
                score3: data.score3
            }));
        } else {
            Order storage order = orders[orderId];
            require(order.claimedShareAmount == 0, 'claimed order does not change');
            if(isFromTicket) {
                tickets[data.user] -= order.ticketAmount;
                require(tickets[data.user] + data.ticketAmount <= IRewardSource(rewardSource).tickets(data.user), 'ticket overflow');
            }
            ticketTotal = ticketTotal.sub(order.ticketAmount).add(data.ticketAmount);
            order.ticketAmount = data.ticketAmount;
            order.score = data.score;
            order.score1 = data.score1;
            order.score2 = data.score2;
            order.score3 = data.score3;
        }

        if(isFromTicket) {
            tickets[data.user] += data.ticketAmount;
        }
    }

    function uploadBatch(PlayData[] calldata datas) external onlyUploader {
        for(uint128 i; i < datas.length; i++) {
            uploadOne(datas[i]);
        }
    }
 
    function uploaded(uint64 _startTime, uint128 _ticketTotal) external onlyUploader {
        require(_ticketTotal > 0, 'ticketTotal zero');
        require(ticketTotal == _ticketTotal, 'invalid ticketTotal');
        require(block.timestamp > _startTime, 'invalid start time');
        require(epoch > 0, 'epoch zero');
        require(block.number <= type(uint64).max, 'stop');
        
        if(totalRound > 0) {
            RoundData memory last = historys[totalRound-1];
            require(block.timestamp >= last.startTime + epoch, 'must be >= interval');
            require(_startTime >= last.startTime + epoch, 'interval time error');
        }
        RoundData storage currentRound = historys[totalRound];

        require(currentRound.ticketTotal == 0, 'already uploaded');

        currentRound.startTime = _startTime;
        currentRound.ticketTotal = _ticketTotal;
        currentRound.strategySn = totalStrategy;
        currentRound.releaseBlockStart = uint64(block.number);
        currentRound.releaseBlockEnd = currentRound.releaseBlockStart + shareReleaseEpoch;

        uint rewardAmount = IRewardSource(rewardSource).getBalance();
        uint128 reward;
        if(rewardAmount > 0) {
            (uint _reward, ) = IRewardSource(rewardSource).withdraw(rewardAmount);
            reward = uint128(_reward);
        }
        
        currentRound.rewardTotal = reward;
        ticketTotal = 0;
        emit NewRound(totalRound); 
        totalRound++;
    }

    function canClaim(uint128 _orderId) public view returns (bool) {
        OrderResult memory order = getOrderResult(_orderId);
        RoundData memory round = historys[order.roundNumber];
        if(round.ticketTotal == 0) {
            return false;
        }

        if(order.claimShareAmount > 0 && order.claimedShareAmount.add(order.claimShareAvaliable) <= order.claimShareAmount) {
            return true;
        }

        return false;
    }
  
    function _claim(uint128 _orderId) internal returns (address to, uint128 winAmount, uint128 shareAmount) {
        Order storage order = orders[_orderId];
        RoundData memory round = historys[order.roundNumber];
        require(order.user == msg.sender || order.user == address(0), 'forbidden');
        require(round.ticketTotal > 0, 'not ready');
        require(canClaim(_orderId), 'can not claim');
        to = order.user;
        if(order.user == address(0)) {
            to = team();
        }
        OrderResult memory result = getOrderResult(_orderId);
        if(result.claimShareAvaliable > 0 && result.claimedShareAmount.add(result.claimShareAvaliable) <= result.claimShareAmount) {
            shareAmount = shareAmount.add(result.claimShareAvaliable);
            order.claimedShareAmount = result.claimedShareAmount.add(result.claimShareAvaliable);
        }

        emit Claimed(to, _orderId, 0, shareAmount);
    }

    function _transferForClaim(address to, uint128 winAmount, uint128 shareAmount) internal returns (uint128, uint128) {
        if(winAmount > 0) {
        }

        if(shareAmount > 0) {
            require(IShareToken(shareToken).take() >= shareAmount, 'share stop');
            IShareToken(shareToken).mint(to, shareAmount);
        }
        return (winAmount, shareAmount);
    }


    function claim(uint128 _orderId) external returns (uint128 winAmount, uint128 shareAmount) {
        (address to, uint128 _winAmount, uint128 _shareAmount) = _claim(_orderId);
        return _transferForClaim(to, _winAmount, _shareAmount);
    }

    function _claimAll(address _to, uint128 _start, uint128 _end) internal returns (uint128 winAmount, uint128 shareAmount) {
        require(_start <= _end && _start >= 0 && _end >= 0, "invalid param");
        uint128 count = countUserOrder(_to);
        if (_end > count) _end = count;
        if (_start > _end) _start = _end;
        count = _end - _start;
        if (count == 0) return (0,0);
        for(uint128 i = _start; i < _end; i++) {
            uint128 orderId = userOrders[_to][i];
            if(canClaim(orderId)) {
                (,, uint128 _share) = _claim(orderId);
                shareAmount = shareAmount.add(_share);
            }
        }
        return _transferForClaim(_to, winAmount, shareAmount);
    }

    function claimAll(uint128 _start, uint128 _end) external returns (uint128 winAmount, uint128 shareAmount) {
        return _claimAll(msg.sender, _start, _end);
    }

    function claimAllForZero(uint128 _start, uint128 _end) external returns (uint128 winAmount, uint128 shareAmount) {
        return _claimAll(address(0), _start, _end);
    }

    function withdraw(uint _value) external virtual override nonReentrant whenNotPaused returns (uint reward, uint fee) {
        require(msg.sender == nextPool, 'forbidden');
        require(_value > 0, 'zero');
        require(getBalance() >= _value, 'insufficient balance');

        reward = _value;
        if (buyToken == address(0)) {
            TransferHelper.safeTransferETH(nextPool, reward);
        } else {
            TransferHelper.safeTransfer(buyToken, nextPool, reward);
        }
        emit Withdrawed(nextPool, reward, team(), fee);
    }

    function getBalance() public view virtual override returns (uint) {
        uint balance = address(this).balance;
        if(buyToken != address(0)) {
            balance = IERC20(buyToken).balanceOf(address(this));
        }
        return balance;
    }

    function countUserOrder(address _user) public view returns (uint128) {
        return uint128(userOrders[_user].length);
    }

    function iterateReverseUserOrders(address _user, uint128 _start, uint128 _end) external view returns (OrderResult[] memory list){
        require(_end <= _start && _end >= 0 && _start >= 0, "invalid param");
        uint128 count = countUserOrder(_user);
        if (_start > count) _start = count;
        if (_end > _start) _end = _start;
        count = _start - _end; 
        list = new OrderResult[](count);
        if (count == 0) return list;
        uint128 index = 0;
        for(uint128 i = _end;i < _start; i++) {
            uint128 j = _start - index -1;
            list[index] = getOrderResult(userOrders[_user][j]);
            index++;
        }
        return list;
    }

    function countRoundOrder(uint128 _round) public view returns (uint128) {
        return uint128(roundOrders[_round].length);
    }

    function iterateReverseRoundOrders(uint128 _round, uint128 _start, uint128 _end) external view returns (OrderResult[] memory list){
        require(_end <= _start && _end >= 0 && _start >= 0, "invalid param");
        uint128 count = countRoundOrder(_round);
        if (_start > count) _start = count;
        if (_end > _start) _end = _start;
        count = _start - _end; 
        list = new OrderResult[](count);
        if (count == 0) return list;
        uint128 index = 0;
        for(uint128 i = _end;i < _start; i++) {
            uint128 j = _start - index -1;
            list[index] = getOrderResult(roundOrders[_round][j]);
            index++;
        }
        return list;
    }

    function getOrderResult(uint128 _orderId) public view returns (OrderResult memory) {
        Order memory order = orders[_orderId];
        RoundData memory round = historys[order.roundNumber];
        Rate memory rate = strategies[round.strategySn];

        uint128 claimShareAmount = uint128(order.score) * rate.score + uint128(order.score1) * rate.score1 + uint128(order.score2) * rate.score2 + uint128(order.score3) * rate.score3;
        uint128 canClaimShareAmount;
        if(shareReleaseEpoch == 0 || round.releaseBlockEnd == 0) {
            canClaimShareAmount = claimShareAmount;
        } else {
            uint128 totalDue = uint128(round.releaseBlockEnd - round.releaseBlockStart);
            uint128 passedDue = uint128(block.number - round.releaseBlockStart);
            if(passedDue > totalDue) {
                passedDue = totalDue;
            }
            canClaimShareAmount = SafeMath128.mulAndDiv(claimShareAmount, passedDue, totalDue); 
        }

        uint128 claimShareAvaliable = canClaimShareAmount.sub(order.claimedShareAmount);
        
        OrderResult memory result = OrderResult({
            orderId: _orderId,
            roundNumber: order.roundNumber,
            startTime: round.startTime,
            user: order.user,
            ticketAmount: order.ticketAmount,
            score: order.score,
            score1: order.score1,
            score2: order.score2,
            score3: order.score3,
            claimShareAmount: claimShareAmount,
            claimedShareAmount: order.claimedShareAmount,
            claimShareAvaliable: claimShareAvaliable
        });
        return result;
    }

    function getRate(uint128 _strategySn) external view returns (Rate memory) {
        return strategies[_strategySn];
    }

    function getBuyTokenBalance(uint128 _amount) public view returns (uint128) {
        uint128 balance = uint128(address(this).balance);
        if(buyToken != address(0)) {
            balance = uint128(IERC20(buyToken).balanceOf(address(this)));
        }
        if(_amount > balance) {
            _amount = balance;
        }
        return _amount;
    }
}
