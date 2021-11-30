// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;
pragma experimental ABIEncoderV2;

import "./libraries/SafeMath128.sol";
import './modules/Initializable.sol';
import './modules/Configable.sol';
import './interfaces/IERC20.sol';
import './interfaces/IGamePool.sol';


contract GamePoolShareRule is Configable, Initializable {
    using SafeMath128 for uint128;

    struct ShareRule {
        address pool;
        bool enabled;
        uint128 startTime;
        uint128 participationAmount;
        uint128 topAmount;
        uint128 weekNumber;
        uint128 weekIncreaseAmount;
        uint128 weekDecreaseRate;
    }
    
    mapping(address => ShareRule) public shareRule;
 
    function initialize() external initializer {
        owner = msg.sender;
    }

    function setShareRule(ShareRule memory _rule) public onlyManager {
        require(_rule.weekDecreaseRate <= 10000, 'invalid weekDecreaseRate');
        shareRule[_rule.pool] = _rule;
    }

    function setShareRules(ShareRule[] memory _rules) external onlyManager {
        require(_rules.length > 0, 'invalid param');
        for(uint i; i<_rules.length; i++) {
            setShareRule(_rules[i]);
        }
    }

    function getShareRule(address _pool) public view returns (ShareRule memory) {
        return shareRule[_pool];
    }

    function getShareRules(address[] calldata  _pools) external view returns (ShareRule[] memory res) {
        res = new ShareRule[](_pools.length);
        for(uint i; i<_pools.length; i++) {
            res[i] = getShareRule(_pools[i]);
        }
        return res;
    }

    function getShareAmount(address _pool) public view returns (uint128 participationAmount, uint128 topAmount) {
        participationAmount = IGamePool(_pool).shareParticipationAmount();
        topAmount = IGamePool(_pool).shareTopAmount();

        ShareRule memory _rule = shareRule[_pool];
        if(!_rule.enabled) {
            return (participationAmount, topAmount);
        }
        participationAmount = computeShareAmount(_pool, _rule.participationAmount, uint128(block.timestamp));
        topAmount = computeShareAmount(_pool, _rule.topAmount, uint128(block.timestamp));  
    }

    function computeShareAmount(address _pool, uint128 _amount, uint128 _endTime) public view returns (uint128 amount) {
        if(_amount == 0) return 0;
        ShareRule memory _rule = shareRule[_pool];
        require(_endTime > _rule.startTime, 'invaild time');
        require(_rule.weekNumber > 0, 'invaild weekNumber');
        uint128 elapsed = _endTime - _rule.startTime;
        uint128 times = elapsed / uint128(1 weeks);
        if(times < _rule.weekNumber) {
            amount = _amount.add(times * _rule.weekIncreaseAmount);
        } else {
            uint128 maxAmount = _amount.add((_rule.weekNumber-1) * _rule.weekIncreaseAmount);
            uint128 decreaseAmount = maxAmount.mul((times + 1 - _rule.weekNumber ) * _rule.weekDecreaseRate).div(10000);
            if(decreaseAmount >= maxAmount) {
                amount = 0;
            } else {
                amount = maxAmount.sub(decreaseAmount);
                uint _decimals = 18;
                if(IGamePool(_rule.pool).shareToken() != address(0)) {
                    _decimals = uint(IERC20(IGamePool(_rule.pool).shareToken()).decimals());
                }
                if(amount < uint128(10**_decimals)) {
                    amount = 0;
                }
            }
        }
        return amount;
    }
}
