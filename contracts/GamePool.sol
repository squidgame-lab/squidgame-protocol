// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;
pragma experimental ABIEncoderV2;

import "./libraries/SafeMath.sol";
import './libraries/TransferHelper.sol';
import './modules/ReentrancyGuard.sol';
import './modules/Pausable.sol';
import './modules/Configable.sol';
import './modules/Initializable.sol';
import './interfaces/IERC20.sol';
import './interfaces/IRewardSource.sol';
import './interfaces/IShareToken.sol';

contract GamePool is IRewardSource, Configable, Pausable, ReentrancyGuard, Initializable {
    using SafeMath for uint;
    address public rewardSource;
    address public override buyToken;
    address public shareToken;
    address public nextPool;
    uint public nextPoolRate;
    uint public nextPoolTotal;
    uint public epoch;
    uint public totalRound;
    uint public shareParticipationAmount;
    uint public shareTopAmount;
    uint public shareReleaseEpoch;
    mapping(address => uint) public override tickets;
    bool public isFromTicket;
    
    struct PlayData {
        address user;
        uint rank;
        uint ticketAmount;
        uint score;
    }
    
    struct RoundData {
        uint startTime;
        uint ticketTotal;
        uint winTotal;
        uint rewardTotal;
        uint scoreTotal;
        uint topScoreTotal;
        uint topStrategySn;
        uint shareParticipationAmount;
        uint shareTopAmount;
    }

    struct Order {
        uint roundNumber;
        address user;
        uint rank;
        uint ticketAmount;
        uint score;
        uint claimedWin;
        uint claimedShareParticipationAmount;
        uint claimedShareTopAmount;
    }

    struct OrderResult {
        uint orderId;
        uint roundNumber;
        uint startTime;
        address user;
        uint rank;
        uint ticketAmount;
        uint score;
        uint claimedWin;
        uint claimedShareParticipationAmount;
        uint claimedShareTopAmount;
        uint claimWin;
        uint claimShareParticipationAmount;
        uint claimShareTopAmount;
        uint claimShareTopAvaliable;
    }

    struct TopRate {
        uint rate;
        uint start;
        uint end;
    }

    Order[] public orders;
    uint public totalTopStrategy;
    mapping (uint => TopRate[]) public topStrategies;
    mapping (uint => RoundData) public historys;
    mapping (address => uint[]) public userOrders;
    mapping (uint => uint[]) public roundOrders;
    mapping (address => mapping (uint => uint)) public userRoundOrderMap;

    event NewRound(uint indexed value);
    event Claimed(address indexed user, uint indexed orderId, uint winAmount, uint shareAmount);

    receive() external payable {
    }
 
    function initialize() external initializer {
        owner = msg.sender;
    }

    function configure(address _rewardSource, address _shareToken, address _nextPool, uint _nextPoolRate, uint _epoch, uint _shareReleaseEpoch, bool _isFromTicket) external onlyDev {
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
    }

    function setNexPoolRate(uint _nextPoolRate) external onlyManager {
        require(_nextPoolRate != nextPoolRate, 'no change');
        nextPoolRate = _nextPoolRate;
    }

    function setShareAmount(uint _shareParticipationAmount, uint _shareTopAmount) external onlyManager {
        require(shareParticipationAmount != _shareParticipationAmount || shareTopAmount != _shareTopAmount, 'no change');
        shareParticipationAmount = _shareParticipationAmount;
        shareTopAmount = _shareTopAmount;
    }

    function setTopRate(uint[] calldata _levels, TopRate[] memory _values) external onlyManager {
        require(_levels.length > 0  && _levels.length == _values.length, 'invalid param');
        totalTopStrategy++;
        for(uint i; i<_levels.length+1; i++) {
            topStrategies[totalTopStrategy].push(TopRate({
                rate: 0,
                start: 0,
                end: 0
            }));
        }
        
        uint _total;
        for(uint i; i<_levels.length; i++) {
            topStrategies[totalTopStrategy][_levels[i]] = _values[i];
            _total = _total.add(_values[i].rate);
        }

        require(_total == 100, 'sum of rate is not 100');
    }

    function getTopEndInStrategy(uint _sn) public view returns (uint) {
        if(totalTopStrategy > 0 && topStrategies[_sn].length > 0) {
            return topStrategies[_sn][topStrategies[_sn].length -1].end;
        }
        return 0;
    }

    function getTopEnd() external view returns (uint) {
        return getTopEndInStrategy(totalTopStrategy);
    }

    function uploadOne(PlayData memory data) public onlyUploader {
        require(data.user != address(0), 'invalid param');
        if(isFromTicket) {
            require(tickets[data.user].add(data.ticketAmount) <= IRewardSource(rewardSource).tickets(data.user), 'ticket overflow');
        }
        uint orderId = userRoundOrderMap[data.user][totalRound];
        bool exist;
        if(orderId > 0 || (orderId == 0 && totalRound == 0 && userOrders[data.user].length > 0)) {
            exist = true;
        }

        if(!exist) {
            userRoundOrderMap[data.user][totalRound] = orders.length;
            if(userOrders[data.user].length == 0) {
                userOrders[data.user] = new uint[](1);
                userOrders[data.user][0] = orders.length;
            } else {
                userOrders[data.user].push(orders.length);
            }

            if(roundOrders[totalRound].length == 0) {
                roundOrders[totalRound] = new uint[](1);
                roundOrders[totalRound][0] = orders.length;
            } else {
                roundOrders[totalRound].push(orders.length);
            }

            orders.push(Order({
                roundNumber: totalRound,
                user: data.user,
                rank: data.rank,
                ticketAmount: data.ticketAmount,
                score: data.score,
                claimedWin: 0,
                claimedShareParticipationAmount: 0,
                claimedShareTopAmount: 0
            }));
        } else {
            Order storage order = orders[orderId];
            require(order.claimedWin == 0 && order.claimedShareParticipationAmount == 0 && order.claimedShareTopAmount == 0, 'claimed order does not change');
            if(isFromTicket) {
                tickets[data.user] = tickets[data.user].sub(order.ticketAmount);
            }
            order.rank = data.rank;
            order.ticketAmount = data.ticketAmount;
            order.score = data.score;
        }

        if(isFromTicket) {
            tickets[data.user] = tickets[data.user].add(data.ticketAmount);
        }
    }

    function uploadBatch(PlayData[] calldata datas) external onlyUploader {
        for(uint i; i < datas.length; i++) {
            uploadOne(datas[i]);
        }
    }
 
    function uploaded(uint _startTime, uint _ticketTotal, uint _scoreTotal, uint _topScoreTotal) external onlyUploader {
        require(_ticketTotal > 0, 'ticketTotal zero');
        require(block.timestamp > _startTime, 'invalid start time');
        require(epoch > 0, 'epoch zero');
        
        if(totalRound > 0) {
            RoundData memory last = historys[totalRound-1];
            require(block.timestamp >= last.startTime.add(epoch), 'must be >= interval');
            require(_startTime >= last.startTime.add(epoch), 'interval time error');
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
        (uint reward, ) = IRewardSource(rewardSource).withdraw(rewardAmount);
        if(nextPoolRate > 0) {
            uint nextPoolReward = reward.div(nextPoolRate);
            reward = reward.sub(nextPoolReward);
            nextPoolTotal = nextPoolTotal.add(nextPoolReward);
        }
        currentRound.rewardTotal = reward;

        emit NewRound(totalRound); 
        totalRound++;
    }

    function canClaim(uint _orderId) public view returns (bool) {
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
  
    function _claim(uint _orderId) internal returns (uint winAmount, uint shareAmount) {
        Order storage order = orders[_orderId];
        RoundData memory round = historys[order.roundNumber];
        require(order.user == msg.sender || order.user == address(0), 'forbidden');
        require(round.ticketTotal > 0, 'not ready');
        require(order.ticketAmount > 0, "no participate in this round");
        require(canClaim(_orderId), 'can not claim');
        address to = order.user;
        if(order.user == address(0)) {
            to = team();
        }
        OrderResult memory result = getOrderResult(_orderId);
        if(result.claimWin > 0 && order.claimedWin == 0) {
            if(buyToken == address(0)) {
                TransferHelper.safeTransferETH(to, result.claimWin);
            } else {
                TransferHelper.safeTransfer(buyToken, to, result.claimWin);
            }
            order.claimedWin = result.claimWin;
            winAmount = result.claimWin;
        }

        if(result.claimShareParticipationAmount > 0 && order.claimedShareParticipationAmount == 0) {
            shareAmount = shareAmount.add(result.claimShareParticipationAmount);
            order.claimedShareParticipationAmount = result.claimShareParticipationAmount;
        }

        if(result.claimShareTopAvaliable > 0 && order.claimedShareTopAmount.add(result.claimShareTopAvaliable) <= result.claimShareTopAmount) {
            shareAmount = shareAmount.add(result.claimShareTopAvaliable);
            order.claimedShareTopAmount = order.claimedShareTopAmount.add(result.claimShareTopAvaliable);
        }

        if(shareAmount > 0) {
            require(IShareToken(shareToken).take() >= shareAmount, 'share stop');
            IShareToken(shareToken).mint(to, shareAmount);
        }
        
        emit Claimed(to, _orderId, winAmount, shareAmount);
    }

    function claim(uint _orderId) external returns (uint winAmount, uint shareAmount) {
        return _claim(_orderId);
    }

    function _claimAll(address _to, uint _start, uint _end) internal returns (uint winAmount, uint shareAmount) {
        require(_start <= _end && _start >= 0 && _end >= 0, "invalid param");
        uint count = countUserOrder(_to);
        if (_end > count) _end = count;
        if (_start > _end) _start = _end;
        count = _end - _start;
        if (count == 0) return (0,0);
        uint index = 0;
        for(uint i = _start; i < _end; i++) {
            uint orderId = userOrders[_to][i];
            if(canClaim(orderId)) {
                (uint _win, uint _share) = _claim(orderId);
                winAmount = winAmount.add(_win);
                shareAmount = shareAmount.add(_share);
            }
            index++;
        }
    }

    function claimAll(uint _start, uint _end) external returns (uint winAmount, uint shareAmount) {
        return _claimAll(msg.sender, _start, _end);
    }

    function claimAllForZero(uint _start, uint _end) external returns (uint winAmount, uint shareAmount) {
        return _claimAll(address(0), _start, _end);
    }

    function withdraw(uint _value) external virtual override nonReentrant whenNotPaused returns (uint reward, uint fee) {
        require(msg.sender == nextPool, 'forbidden');
        require(_value > 0, 'zero');
        require(getBalance() >= _value, 'insufficient balance');

        reward = _value;
        nextPoolTotal = nextPoolTotal.sub(reward);
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

    function countUserOrder(address _user) public view returns (uint) {
        return userOrders[_user].length;
    }

    function iterateReverseUserOrders(address _user, uint _start, uint _end) external view returns (OrderResult[] memory list){
        require(_end <= _start && _end >= 0 && _start >= 0, "invalid param");
        uint count = countUserOrder(_user);
        if (_start > count) _start = count;
        if (_end > _start) _end = _start;
        count = _start - _end; 
        list = new OrderResult[](count);
        if (count == 0) return list;
        uint index = 0;
        for(uint i = _end;i < _start; i++) {
            uint j = _start - index -1;
            list[index] = getOrderResult(userOrders[_user][j]);
            index++;
        }
        return list;
    }

    function countRoundOrder(uint _round) public view returns (uint) {
        return roundOrders[_round].length;
    }

    function iterateRoundOrders(uint _round, uint _start, uint _end) external view returns (OrderResult[] memory list){
        require(_start <= _end && _start >= 0 && _end >= 0, "invalid param");
        uint count = countRoundOrder(_round);
        if (_end > count) _end = count;
        if (_start > _end) _start = _end;
        count = _end - _start;
        list = new OrderResult[](count);
        if (count == 0) return list;
        uint index = 0;
        for(uint i = _start; i < _end; i++) {
            list[index] = getOrderResult(roundOrders[_round][i]);
            index++;
        }
        return list;
    }

    function getRankTopRate(uint _strategySn, uint _rank) public view returns (uint rate, uint count) {
        for(uint i; i<topStrategies[_strategySn].length; i++) {
            if(_rank >= topStrategies[_strategySn][i].start && _rank <= topStrategies[_strategySn][i].end) {
                rate = topStrategies[_strategySn][i].rate;
                count = topStrategies[_strategySn][i].end.sub(topStrategies[_strategySn][i].start).add(1);
                return (rate, count);
            }
        }
        return (rate, count);
    }

    function getOrderResult(uint _orderId) public view returns (OrderResult memory) {
        Order memory order = orders[_orderId];
        RoundData memory round = historys[order.roundNumber];
        uint topEnd = getTopEndInStrategy(round.topStrategySn);
        uint claimWin;
        if(round.topScoreTotal > 0 && order.rank <= topEnd) {
            claimWin = order.score.mul(round.rewardTotal).div(round.topScoreTotal);
        }

        uint claimShareParticipationAmount;
        if(round.ticketTotal > 0) {
            claimShareParticipationAmount = order.ticketAmount.mul(round.shareParticipationAmount).div(round.ticketTotal);
        }

        uint claimShareTopAmount;
        (uint rate, uint count) = getRankTopRate(round.topStrategySn, order.rank);
        if(topEnd > 0 && count > 0 && order.rank <= topEnd) {
            claimShareTopAmount = rate.mul(round.shareTopAmount).div(100).div(count);
        }

        uint canClaimShareTopAmount;
        if(shareReleaseEpoch == 0) {
            canClaimShareTopAmount = claimShareTopAmount;
        } else {
            uint totalDue = epoch.div(shareReleaseEpoch);
            uint passedDue = block.timestamp.sub(round.startTime).div(shareReleaseEpoch);
            if(passedDue > totalDue) {
                passedDue = totalDue;
            }
            canClaimShareTopAmount = claimShareTopAmount.mul(passedDue).div(totalDue); 
        }

        uint claimShareTopAvaliable = canClaimShareTopAmount.sub(order.claimedShareTopAmount);
        
        OrderResult memory result = OrderResult({
            orderId: _orderId,
            roundNumber: order.roundNumber,
            startTime: round.startTime,
            user: order.user,
            rank: order.rank,
            ticketAmount: order.ticketAmount,
            score: order.score,
            claimedWin: order.claimedWin,
            claimedShareParticipationAmount: order.claimedShareParticipationAmount,
            claimedShareTopAmount: order.claimedShareTopAmount,
            claimWin: claimWin,
            claimShareParticipationAmount: claimShareParticipationAmount,
            claimShareTopAmount: claimShareTopAmount,
            claimShareTopAvaliable: claimShareTopAvaliable
        });
        return result;
    }

    function getTopRates(uint _strategySn) external view returns (TopRate[] memory) {
        return topStrategies[_strategySn];
    }
}