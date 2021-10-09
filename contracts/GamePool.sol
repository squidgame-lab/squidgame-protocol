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
    uint public epoch;
    uint public totalRound;
    uint public rewardRate;
    mapping(address => uint) public override tickets;
    bool public isCheckTicket;
    
    struct PlayData {
        address user;
        uint ticketAmount;
        uint winAmount;
        bool claimed;
    }
    
    struct RoundData {
        uint startTime;
        uint ticketTotal;
        uint winTotal;
        uint rewardTotal;
    }

    struct Order {
        uint roundNumber;
        address user;
        uint ticketAmount;
        uint winAmount;
        bool claimed;
    }

    struct OrderResult {
        uint roundNumber;
        address user;
        uint ticketAmount;
        uint winAmount;
        bool claimed;
        uint claimWin;
        uint claimShare;
    }

    Order[] public orders;
    
    mapping (uint => RoundData) public historys;
    mapping (address => uint[]) public userOrders;
    mapping (uint => uint[]) public roundOrders;
    mapping (address => mapping (uint => uint)) public userRoundOrderMap;

    event NewRound(uint indexed value);
    event Claimed(address indexed user, uint indexed orderId, uint win, uint share);

    receive() external payable {
    }
 
    function initialize() external initializer {
        owner = msg.sender;
    }

    function configure(address _rewardSource, address _shareToken, address _nextPool, uint _nextPoolRate, uint _epoch, bool _isCheckTicket) external onlyDev {
        rewardSource = _rewardSource;
        buyToken = IRewardSource(_rewardSource).buyToken();
        shareToken = _shareToken;
        nextPool = _nextPool;
        nextPoolRate = _nextPoolRate;
        epoch = _epoch;
        isCheckTicket = _isCheckTicket;
    }

    function setNexPoolRate(uint _nextPoolRate) external onlyManager {
        require(_nextPoolRate != nextPoolRate, 'no change');
        nextPoolRate = _nextPoolRate;
    }

    function uploadOne(PlayData memory data) public onlyManager {
        require(data.user != address(0), 'invalid param');
        if(isCheckTicket) {
            require(tickets[data.user].add(data.ticketAmount) <= IRewardSource(rewardSource).tickets(data.user), 'ticket overflow');
        }
        uint orderId = userRoundOrderMap[data.user][totalRound];
        if(orderId == 0 && userOrders[data.user].length == 0) {
            userRoundOrderMap[data.user][totalRound] = orders.length;
            userOrders[data.user] = new uint[](1);
            userOrders[data.user][0] = orders.length;
            roundOrders[totalRound] = new uint[](1);
            roundOrders[totalRound][0] = orders.length;
            orders.push(Order({
                roundNumber: totalRound,
                user: data.user,
                ticketAmount: data.ticketAmount,
                winAmount: data.winAmount,
                claimed: false
            }));
        } else {
            Order storage order = orders[orderId];
            if(isCheckTicket) {
                tickets[data.user] = tickets[data.user].sub(order.ticketAmount);
            }
            order.ticketAmount = data.ticketAmount;
            order.winAmount = data.winAmount;
            order.claimed = false;
        }

        if(isCheckTicket) {
            tickets[data.user] = tickets[data.user].add(data.ticketAmount);
        }
    }

    function uploadBatch(PlayData[] calldata datas) external onlyManager {
        for(uint i; i < datas.length; i++) {
            uploadOne(datas[i]);
        }
    }
 
    function uploaded(uint _startTime, uint _ticketTotal, uint _winTotal, uint _rewardTotal) external onlyManager {
        require(_ticketTotal > 0 && _rewardTotal >0, 'zero');
        
        if(totalRound > 0) {
            RoundData memory last = historys[totalRound-1];
            require(block.timestamp >= last.startTime.add(epoch), 'must be >= interval');
            require(_startTime >= last.startTime.add(epoch), 'interval time error');
        }
        RoundData storage currentRound = historys[totalRound];

        require(currentRound.ticketTotal == 0, 'already uploaded');

        currentRound.startTime = _startTime;
        currentRound.ticketTotal = _ticketTotal;
        currentRound.winTotal = _winTotal;

        if(_rewardTotal > 0) {
            (uint reward, ) = IRewardSource(rewardSource).withdraw(_rewardTotal);
            if(nextPoolRate > 0) {
                uint nextPoolReward = reward.div(nextPoolRate);
                reward = reward.sub(nextPoolReward);
                if (buyToken == address(0)) {
                    if(nextPoolReward > 0) TransferHelper.safeTransferETH(nextPool, nextPoolReward);
                } else {
                    if(nextPoolReward > 0) TransferHelper.safeTransfer(buyToken, nextPool, nextPoolReward);
                }
            }
            currentRound.rewardTotal = reward;
        }

        emit NewRound(totalRound); 
        totalRound++;
    }

    function canClaim(uint _orderId) public view returns (bool) {
        Order memory order = orders[_orderId];
        RoundData memory round = historys[order.roundNumber];
        if(!order.claimed && order.ticketAmount > 0 && round.ticketTotal > 0) {
            return true;
        }
        return false;
    }

    function queryClaim(uint _orderId) public view returns (uint winAmount, uint share) {
        if(!canClaim(_orderId)) return (0, 0);
        Order memory order = orders[_orderId];
        RoundData memory round = historys[order.roundNumber];
        
        if(order.winAmount > 0) {
            winAmount = order.winAmount.mul(round.rewardTotal).div(round.winTotal);
        }

        share = order.ticketAmount.mul(rewardRate).div(1e18).div(round.ticketTotal);
        if(IShareToken(shareToken).take() < share) {
            share = 0;
        }
    }
  
    function _claim(uint _orderId) internal returns (uint winAmount, uint share) {
        Order storage order = orders[_orderId];
        RoundData memory round = historys[order.roundNumber];
        require(order.user == msg.sender, 'forbidden');
        require(round.ticketTotal > 0, 'not ready');
        require(!order.claimed, "already claimed");
        require(order.ticketAmount > 0, "no participate in this round");
        order.claimed = true;

        if(order.winAmount > 0) {
            winAmount = order.winAmount.mul(round.rewardTotal).div(round.winTotal);
            TransferHelper.safeTransfer(buyToken, msg.sender, winAmount);
        }

        share = order.ticketAmount.mul(rewardRate).div(1e18).div(round.ticketTotal);
        require(IShareToken(shareToken).take() >= share, 'stop');
        if(share > 0) IShareToken(shareToken).mint(msg.sender, share);
        emit Claimed(msg.sender, _orderId, winAmount, share);
    }

    function claim(uint _orderId) external returns (uint winAmount, uint share) {
        return _claim(_orderId);
    }

    function claimAll(uint _start, uint _end) external returns (uint winAmount, uint share) {
        require(_start <= _end && _start >= 0 && _end >= 0, "invalid param");
        uint count = countUserOrder(msg.sender);
        if (_end > count) _end = count;
        if (_start > _end) _start = _end;
        count = _end - _start;
        if (count == 0) return (0,0);
        uint index = 0;
        for(uint i = _start; i < _end; i++) {
            uint orderId = userOrders[msg.sender][i];
            if(canClaim(orderId)) {
                (uint _win, uint _share) = _claim(orderId);
                winAmount = winAmount.add(_win);
                share = share.add(_share);
            }
            index++;
        }
    }

    function withdraw(uint _value) external virtual override nonReentrant whenNotPaused returns (uint reward, uint fee) {
        require(msg.sender == nextPool, 'forbidden');
        require(_value > 0, 'zero');
        require(getBalance() >= _value, 'insufficient balance');

        reward = _value;
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

    function getOrderResult(uint _orderId) public view returns (OrderResult memory) {
        Order memory order = orders[_orderId];
        (uint _win, uint _share) = queryClaim(_orderId);
        OrderResult memory result = OrderResult({
            roundNumber: order.roundNumber,
            user: order.user,
            ticketAmount: order.ticketAmount,
            winAmount: order.winAmount,
            claimed: order.claimed,
            claimWin: _win,
            claimShare: _share
        });
        return result;
    }
}