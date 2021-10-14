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

contract GamePool is IRewardSource, Configable, Pausable, ReentrancyGuard, Initializable {
    using SafeMath128 for uint128;
    address public rewardSource;
    address public override buyToken;
    address public shareToken;
    address public nextPool;
    uint128 public nextPoolRate;
    uint128 public nextPoolTotal;
    uint64 public epoch;
    uint64 public totalRound;
    uint128 public shareParticipationAmount;
    uint128 public shareTopAmount;
    uint64 public shareReleaseEpoch;
    mapping(address => uint) public override tickets;
    bool public isFromTicket;
    
    struct PlayData {
        address user;
        uint32 rank;
        uint32 score;
        uint128 ticketAmount;
    }
    
    struct RoundData {
        uint128 ticketTotal;
        uint128 winTotal;
        uint128 rewardTotal;
        uint128 scoreTotal;
        uint128 topScoreTotal;
        uint128 topStrategySn;
        uint128 shareParticipationAmount;
        uint128 shareTopAmount;
        uint64 startTime;
    }

    struct Order {
        address user;
        uint64 roundNumber;
        uint32 rank;
        uint32 score;
        uint128 ticketAmount;
    }

    struct OrderResult {
        address user;
        uint128 orderId;
        uint64 roundNumber;
        uint64 startTime;
        uint64 rank;
        uint64 score;
        uint128 ticketAmount;
        uint128 claimedWin;
        uint128 claimedShareParticipationAmount;
        uint128 claimedShareTopAmount;
        uint128 claimWin;
        uint128 claimShareParticipationAmount;
        uint128 claimShareTopAmount;
        uint128 claimShareTopAvaliable;
    }

    struct TopRate {
        uint128 rate;
        uint64 start;
        uint64 end;
    }

    struct ClaimLog {
        uint128 orderId;
        uint128 claimedWin;
        uint128 claimedShareParticipationAmount;
        uint128 claimedShareTopAmount;
    }

    Order[] public orders;
    uint128 public totalTopStrategy;
    mapping (uint128 => TopRate[]) public topStrategies;
    mapping (uint64 => RoundData) public historys;
    mapping (address => uint128[]) public userOrders;
    mapping (uint128 => uint128[]) public roundOrders;
    mapping (address => mapping (uint128 => uint128)) public userRoundOrderMap;
    mapping (uint128 => ClaimLog) public claimLogs;
    bool public enableRoundOrder;

    event NewRound(uint128 indexed value);
    event Claimed(address indexed user, uint128 indexed orderId, uint128 winAmount, uint128 shareAmount);

    receive() external payable {
    }
 
    function initialize() external initializer {
        owner = msg.sender;
    }

    function configure(address _rewardSource, address _shareToken, address _nextPool, uint128 _nextPoolRate, uint64 _epoch, uint64 _shareReleaseEpoch, bool _isFromTicket, bool _enableRoundOrder) external onlyDev {
        if(_shareReleaseEpoch > 0) {
            require(_epoch % _shareReleaseEpoch == 0, 'invalid _epoch and _shareReleaseEpoch');
        }
        rewardSource = _rewardSource;
        buyToken = IRewardSource(_rewardSource).buyToken();
        shareToken = _shareToken;
        nextPool = _nextPool;
        nextPoolRate = _nextPoolRate;
        epoch = _epoch;
        shareReleaseEpoch = _shareReleaseEpoch;
        isFromTicket = _isFromTicket;
        enableRoundOrder = _enableRoundOrder;
    }

    function setNexPoolRate(uint128 _nextPoolRate) external onlyManager {
        require(_nextPoolRate != nextPoolRate, 'no change');
        nextPoolRate = _nextPoolRate;
    }

    function setShareAmount(uint128 _shareParticipationAmount, uint128 _shareTopAmount) external onlyManager {
        require(shareParticipationAmount != _shareParticipationAmount || shareTopAmount != _shareTopAmount, 'no change');
        shareParticipationAmount = _shareParticipationAmount;
        shareTopAmount = _shareTopAmount;
    }

    function setTopRate(uint128[] calldata _levels, TopRate[] memory _values) external onlyManager {
        require(_levels.length > 0  && _levels.length == _values.length, 'invalid param');
        totalTopStrategy++;
        for(uint128 i; i<_levels.length+1; i++) {
            topStrategies[totalTopStrategy].push(TopRate({
                rate: 0,
                start: 0,
                end: 0
            }));
        }
        
        uint128 _total;
        for(uint128 i; i<_levels.length; i++) {
            topStrategies[totalTopStrategy][_levels[i]] = _values[i];
            _total = _total.add(_values[i].rate);
        }

        require(_total == 100, 'sum of rate is not 100');
    }

    function getTopEndInStrategy(uint128 _sn) public view returns (uint128) {
        if(totalTopStrategy > 0 && topStrategies[_sn].length > 0) {
            return topStrategies[_sn][topStrategies[_sn].length -1].end;
        }
        return 0;
    }

    function getTopEnd() external view returns (uint128) {
        return getTopEndInStrategy(totalTopStrategy);
    }

    function uploadOne(PlayData memory data) public onlyUploader {
        if(isFromTicket) {
            require(tickets[data.user] + data.ticketAmount <= IRewardSource(rewardSource).tickets(data.user), 'ticket overflow');
        }
        uint128 orderId = userRoundOrderMap[data.user][totalRound];
        bool exist;
        if(orderId > 0 || (orderId == 0 && totalRound == 0 && userOrders[data.user].length > 0)) {
            exist = true;
        }

        if(!exist) {
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
                rank: data.rank,
                ticketAmount: data.ticketAmount,
                score: data.score
            }));
        } else {
            require(claimLogs[orderId].claimedWin == 0 && claimLogs[orderId].claimedShareParticipationAmount == 0 && claimLogs[orderId].claimedShareTopAmount == 0, 'claimed order does not change');
            Order storage order = orders[orderId];
            if(isFromTicket) {
                tickets[data.user] -= order.ticketAmount;
            }
            order.rank = data.rank;
            order.ticketAmount = data.ticketAmount;
            order.score = data.score;
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
 
    function uploaded(uint64 _startTime, uint128 _ticketTotal, uint128 _scoreTotal, uint128 _topScoreTotal) external onlyUploader {
        require(_ticketTotal > 0, 'ticketTotal zero');
        require(block.timestamp > _startTime, 'invalid start time');
        require(epoch > 0, 'epoch zero');
        
        if(totalRound > 0) {
            RoundData memory last = historys[totalRound-1];
            require(block.timestamp >= last.startTime + epoch, 'must be >= interval');
            require(_startTime >= last.startTime + epoch, 'interval time error');
        }
        RoundData storage currentRound = historys[totalRound];

        require(currentRound.ticketTotal == 0, 'already uploaded');

        currentRound.startTime = _startTime;
        currentRound.ticketTotal = _ticketTotal;
        currentRound.scoreTotal = _scoreTotal;
        currentRound.topScoreTotal = _topScoreTotal;
        currentRound.topStrategySn = totalTopStrategy;
        currentRound.shareParticipationAmount = shareParticipationAmount;
        currentRound.shareTopAmount = shareTopAmount;

        uint rewardAmount;
        if(isFromTicket) {
            rewardAmount = _ticketTotal;
        } else {
            rewardAmount = IRewardSource(rewardSource).getBalance();
        }
        (uint _reward, ) = IRewardSource(rewardSource).withdraw(rewardAmount);
        uint128 reward = uint128(_reward);
        if(nextPoolRate > 0) {
            uint128 nextPoolReward = reward.div(nextPoolRate);
            reward = reward.sub(nextPoolReward);
            nextPoolTotal = nextPoolTotal.add(nextPoolReward);
        }
        currentRound.rewardTotal = reward;

        emit NewRound(totalRound); 
        totalRound++;
    }

    function canClaim(uint128 _orderId) public view returns (bool) {
        OrderResult memory order = getOrderResult(_orderId);
        RoundData memory round = historys[order.roundNumber];
        if(round.ticketTotal == 0) {
            return false;
        }
        if(order.claimWin > 0 && order.claimedWin == 0) {
            return true;
        }

        if(order.claimShareParticipationAmount > 0 && order.claimedShareParticipationAmount == 0) {
            return true;
        }

        if(order.claimShareTopAmount > 0 && order.claimedShareTopAmount.add(order.claimShareTopAvaliable) <= order.claimShareTopAmount) {
            return true;
        }

        return false;
    }
  
    function _claim(uint128 _orderId) internal returns (uint128 winAmount, uint128 shareAmount) {
        Order memory order = orders[_orderId];
        RoundData memory round = historys[order.roundNumber];
        require(order.user == msg.sender || order.user == address(0), 'forbidden');
        require(round.ticketTotal > 0, 'not ready');
        require(canClaim(_orderId), 'can not claim');
        ClaimLog storage clog = claimLogs[_orderId];
        address to = order.user;
        if(order.user == address(0)) {
            to = team();
        }
        OrderResult memory result = getOrderResult(_orderId);
        if(result.claimWin > 0 && clog.claimedWin == 0) {
            if(buyToken == address(0)) {
                TransferHelper.safeTransferETH(to, result.claimWin);
            } else {
                TransferHelper.safeTransfer(buyToken, to, result.claimWin);
            }
            clog.claimedWin = result.claimWin;
            winAmount = result.claimWin;
        }

        if(result.claimShareParticipationAmount > 0 && clog.claimedShareParticipationAmount == 0) {
            shareAmount = shareAmount.add(result.claimShareParticipationAmount);
            clog.claimedShareParticipationAmount = result.claimShareParticipationAmount;
        }

        if(result.claimShareTopAvaliable > 0 && clog.claimedShareTopAmount.add(result.claimShareTopAvaliable) <= result.claimShareTopAmount) {
            shareAmount = shareAmount.add(result.claimShareTopAvaliable);
            clog.claimedShareTopAmount = clog.claimedShareTopAmount.add(result.claimShareTopAvaliable);
        }

        if(shareAmount > 0) {
            require(IShareToken(shareToken).take() >= shareAmount, 'share stop');
            IShareToken(shareToken).mint(to, shareAmount);
        }
        
        emit Claimed(to, _orderId, winAmount, shareAmount);
    }

    function claim(uint128 _orderId) external returns (uint128 winAmount, uint128 shareAmount) {
        return _claim(_orderId);
    }

    function _claimAll(address _to, uint128 _start, uint128 _end) internal returns (uint128 winAmount, uint128 shareAmount) {
        require(_start <= _end && _start >= 0 && _end >= 0, "invalid param");
        uint128 count = countUserOrder(_to);
        if (_end > count) _end = count;
        if (_start > _end) _start = _end;
        count = _end - _start;
        if (count == 0) return (0,0);
        uint128 index = 0;
        for(uint128 i = _start; i < _end; i++) {
            uint128 orderId = userOrders[_to][i];
            if(canClaim(orderId)) {
                (uint128 _win, uint128 _share) = _claim(orderId);
                winAmount = winAmount.add(_win);
                shareAmount = shareAmount.add(_share);
            }
            index++;
        }
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
        nextPoolTotal = nextPoolTotal.sub(uint128(reward));
        if (buyToken == address(0)) {
            if(reward > 0) TransferHelper.safeTransferETH(nextPool, reward);
        } else {
            if(reward > 0) TransferHelper.safeTransfer(buyToken, nextPool, reward);
        }
        emit Withdrawed(nextPool, reward, team(), fee);
    }

    function getBalance() public view virtual override returns (uint) {
        uint balance = address(this).balance;
        if(buyToken != address(0)) {
            balance = IERC20(buyToken).balanceOf(address(this));
        }
        if(balance > nextPoolTotal) {
            balance = nextPoolTotal;
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

    function getRankTopRate(uint128 _strategySn, uint128 _rank) public view returns (uint128 rate, uint128 count) {
        for(uint128 i; i<topStrategies[_strategySn].length; i++) {
            if(_rank >= topStrategies[_strategySn][i].start && _rank <= topStrategies[_strategySn][i].end) {
                rate = topStrategies[_strategySn][i].rate;
                count = topStrategies[_strategySn][i].end - topStrategies[_strategySn][i].start + 1;
                return (rate, count);
            }
        }
        return (rate, count);
    }

    function getOrderResult(uint128 _orderId) public view returns (OrderResult memory) {
        Order memory order = orders[_orderId];
        RoundData memory round = historys[order.roundNumber];
        ClaimLog memory clog = claimLogs[_orderId];
        uint128 topEnd = getTopEndInStrategy(round.topStrategySn);
        uint128 claimWin;
        if(round.topScoreTotal > 0 && order.rank <= topEnd) {
            claimWin = SafeMath128.mulAndDiv(uint128(order.score), round.rewardTotal, round.topScoreTotal);
        }

        uint128 claimShareParticipationAmount;
        if(round.ticketTotal > 0) {
            claimShareParticipationAmount = SafeMath128.mulAndDiv(order.ticketAmount, round.shareParticipationAmount, round.ticketTotal);
        }

        uint128 claimShareTopAmount;
        (uint128 rate, uint128 count) = getRankTopRate(round.topStrategySn, order.rank);
        if(topEnd > 0 && count > 0 && order.rank <= topEnd) {
            claimShareTopAmount = SafeMath128.mulAndDiv(rate, round.shareTopAmount, uint128(100*count));
        }

        uint128 canClaimShareTopAmount;
        if(shareReleaseEpoch == 0) {
            canClaimShareTopAmount = claimShareTopAmount;
        } else {
            uint128 totalDue = epoch / shareReleaseEpoch;
            uint128 passedDue = uint128((block.timestamp - round.startTime) / shareReleaseEpoch);
            if(passedDue > totalDue) {
                passedDue = totalDue;
            }
            canClaimShareTopAmount = SafeMath128.mulAndDiv(claimShareTopAmount, passedDue, totalDue); 
        }

        uint128 claimShareTopAvaliable = canClaimShareTopAmount.sub(clog.claimedShareTopAmount);
        
        OrderResult memory result = OrderResult({
            orderId: _orderId,
            roundNumber: order.roundNumber,
            startTime: round.startTime,
            user: order.user,
            rank: order.rank,
            ticketAmount: order.ticketAmount,
            score: order.score,
            claimedWin: clog.claimedWin,
            claimedShareParticipationAmount: clog.claimedShareParticipationAmount,
            claimedShareTopAmount: clog.claimedShareTopAmount,
            claimWin: claimWin,
            claimShareParticipationAmount: claimShareParticipationAmount,
            claimShareTopAmount: claimShareTopAmount,
            claimShareTopAvaliable: claimShareTopAvaliable
        });
        return result;
    }

    function getTopRates(uint128 _strategySn) external view returns (TopRate[] memory) {
        return topStrategies[_strategySn];
    }
}