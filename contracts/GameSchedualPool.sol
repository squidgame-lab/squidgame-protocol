// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import "./interfaces/IGameSchedualPool.sol";
import "./interfaces/IShareToken.sol";
import "./interfaces/IGameTimeLock.sol";
import "./modules/Configable.sol";
import "./modules/ReentrancyGuard.sol";
import "./modules/Initializable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./libraries/TransferHelper.sol";

contract GameSchedualPool is IGameSchedualPool, ReentrancyGuard, Configable, Initializable {
    using SafeMath for uint256;

    event LockCreated(address indexed account, uint256 amount, uint256 unlockTime, uint256 lockWeeks);
    event AmountIncreased(address indexed account, uint256 increasedAmount);
    event UnlockTimeIncreased(address indexed account, uint256 newUnlockTime, uint256 newLockWeeks);
    event Withdraw(address indexed account, uint256 amount);
    event Harvest(address indexed account, address to, uint256 amount);
    event SetLockWeights(address indexed account, uint256 lockWeeks, uint256 weight);
    event SetHarvestRate(address indexed account, uint256 oldOne, uint256 newOne);
    event SetTimeLock(address indexed account, address oldOne, address newOne);
    event SetEmissionRate(address indexed user, uint mintPerBlock);

    uint256 public override maxTime;
    address public override depositToken;
    address public override rewardToken;
    address public timeLock;

    uint256 public constant BONUS_MULTIPLIER = 1;
    uint256 public mintPerBlock;
    uint256 public lastBlock;
    uint256 public accRewardPerShare;
    uint256 public depositTokenSupply;
    uint256 public depositTotalPower;
    uint256 public incrementalTotalSupply;
    uint256 public averageLockDur;
    uint256 public harvestRate;

    mapping(address => LockedBalance) public locked;
    /// @notice Mapping of unlockTime => total amount that will be unlocked at unlockTime
    mapping(uint256 => uint256) public scheduledUnlock;
    /// @notice Mapping of lock weeks => weight
    mapping(uint256 => uint256) public lockWeights;

    function initialize(
        address _depositToken,
        address _rewardToken,
        uint256 _maxTime,
        uint256 _mintPerBlock,
        uint256 _startBlock,
        uint256 _harvestRate,
        address _timeLock
    ) external initializer {
        require(_depositToken != address(0) && _rewardToken != address(0) && _timeLock != address(0), "GameSchedualPool: INVALID_ADDRESS");
        require(_maxTime > 0, "GameSchedualPool: ZERO_NUMBER");
        require(_harvestRate <= 100, 'GameSchedualPool: OVER_RATE');
        owner = msg.sender;
        depositToken = _depositToken;
        rewardToken = _rewardToken;
        maxTime = _maxTime;
        mintPerBlock = _mintPerBlock;
        lastBlock = block.number > _startBlock ? block.number : _startBlock;
        harvestRate = _harvestRate;
        timeLock = _timeLock;
    }

    function getTimestampDropBelow(address _account, uint256 _threshold) external view override returns (uint256) {
        LockedBalance memory lockedBalance = locked[_account];
        if (lockedBalance.amount == 0 || lockedBalance.amount < _threshold) {
            return 0;
        }
        return lockedBalance.unlockTime.sub(_threshold.mul(maxTime).div(lockedBalance.amount));
    }

    function balanceOf(address _account) external view returns (uint256) {
        return _balanceOfAtTimestamp(_account, block.timestamp);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupplyAtTimestamp(block.timestamp);
    }

    function getLockedBalance(address _account) external view override returns (LockedBalance memory) {
        return locked[_account];
    }

    function balanceOfAtTimestamp(address _account, uint256 _timestamp) external view override returns (uint256) {
        return _balanceOfAtTimestamp(_account, _timestamp);
    }

    function totalSupplyAtTimestamp(uint256 _timestamp) external view returns (uint256) {
        return _totalSupplyAtTimestamp(_timestamp);
    }

    function pendingReward(address _account) external view override returns (uint256) {
        LockedBalance memory lockedBalance = locked[_account];
        uint256 accRewardPerShareTmp = accRewardPerShare;
        if (block.number > lastBlock && depositTotalPower != 0) {
            uint256 multiplier = getMultiplier(lastBlock, block.number);
            uint256 reward = multiplier.mul(mintPerBlock);
            accRewardPerShareTmp = accRewardPerShareTmp.add(
                reward.mul(1e18).div(depositTotalPower)
            );
        }
        return lockedBalance
                .amount
                .mul(lockWeights[lockedBalance.lockWeeks])
                .div(100)
                .mul(accRewardPerShareTmp)
                .div(1e18)
                .sub(lockedBalance.rewardDebt);
    }

    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256)  {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    function setTimeLock(address _timeLock) external onlyDev {
        require(timeLock != _timeLock && _timeLock != address(0), 'GameSchedualPool: INVALID_ARGS');
        emit SetTimeLock(msg.sender, timeLock, _timeLock);
        timeLock = _timeLock;
    }

    function setHarvestRate(uint256 _harvestRate) external onlyDev {
        require(harvestRate != _harvestRate && _harvestRate <= 100, 'GameSchedualPool: INVALID_ARGS');
        emit SetHarvestRate(msg.sender, harvestRate, _harvestRate);
        harvestRate = _harvestRate;
    }

    function setEmissionRate(uint _mintPerBlock) external onlyDev {
        _update();
        mintPerBlock = _mintPerBlock;
        emit SetEmissionRate(msg.sender, _mintPerBlock);
    }

    function batchSetLockWeights(
        uint256[] memory _lockWeeksArr,
        uint256[] memory _weightArr
    ) external onlyDev {
        require(_lockWeeksArr.length == _weightArr.length, "Arguments length wrong");
        for (uint256 i = 0; i < _lockWeeksArr.length; i++) {
            setLockWeights(_lockWeeksArr[i], _weightArr[i]);
        }
    }

    function setLockWeights(uint256 _lockWeeks, uint256 _weight) public onlyDev {
        lockWeights[_lockWeeks] = _weight;
        emit SetLockWeights(msg.sender, _lockWeeks, _weight);
    }

    function createLock(uint256 _amount, uint256 _weeksCount) external nonReentrant {
        uint256 cw = (block.timestamp / 1 weeks) * 1 weeks + 1 weeks;
        uint256 unlockTime = cw.add(_weeksCount * 1 weeks);

        LockedBalance memory lockedBalance = locked[msg.sender];

        require(_amount > 0 && _weeksCount > 0, "GameSchedualPool: ZERO_VALUE");
        require(lockedBalance.amount == 0, "GameSchedualPool: EXIST_LOCK");
        require(unlockTime <= block.timestamp + maxTime, "GameSchedualPool: OVER_MAX_TIME");
        require(lockWeights[_weeksCount] != 0, "GameSchedualPool: NOT_SUPPORT_WEEKCOUNT");

        _update();

        scheduledUnlock[unlockTime] = scheduledUnlock[unlockTime].add(_amount);
        locked[msg.sender].unlockTime = unlockTime;
        locked[msg.sender].amount = _amount;
        locked[msg.sender].lockWeeks = _weeksCount;
        locked[msg.sender].rewardDebt = _amount
            .mul(lockWeights[_weeksCount])
            .div(100)
            .mul(accRewardPerShare)
            .div(1e18);

        TransferHelper.safeTransferFrom(
            depositToken,
            msg.sender,
            address(this),
            _amount
        );

        depositTokenSupply = depositTokenSupply.add(_amount);
        depositTotalPower = depositTotalPower.add(
            _amount.mul(lockWeights[_weeksCount]).div(100)
        );
        _updateAveLockDur(_amount, _weeksCount);

        emit LockCreated(msg.sender, _amount, unlockTime, _weeksCount);
    }

    function increaseAmount(uint256 _increasedAmount) external nonReentrant {
        LockedBalance memory lockedBalance = locked[msg.sender];

        require(_increasedAmount > 0, "GameSchedualPool: ZERO_VALUE");
        require(lockedBalance.unlockTime > block.timestamp, "GameSchedualPool: EXPIRED_LOCK");

        _update();
        _harvestRewardToken(msg.sender);

        scheduledUnlock[lockedBalance.unlockTime] = scheduledUnlock[lockedBalance.unlockTime].add(_increasedAmount);
        locked[msg.sender].amount = lockedBalance.amount.add(_increasedAmount);
        locked[msg.sender].rewardDebt = locked[msg.sender].amount.mul(lockWeights[lockedBalance.lockWeeks]).div(100).mul(accRewardPerShare).div(1e18);

        TransferHelper.safeTransferFrom(depositToken, msg.sender, address(this), _increasedAmount);
        depositTokenSupply = depositTokenSupply.add(_increasedAmount);
        depositTotalPower = depositTotalPower.add(_increasedAmount.mul(lockWeights[lockedBalance.lockWeeks]).div(100));
        averageLockDur = (incrementalTotalSupply.mul(averageLockDur).div(10).add(_increasedAmount.mul(lockedBalance.lockWeeks))).mul(10).div(incrementalTotalSupply.add(_increasedAmount));
        incrementalTotalSupply = incrementalTotalSupply.add(_increasedAmount);
        
        emit AmountIncreased(msg.sender, _increasedAmount);
    }

    function increaseUnlockTime(uint256 _increasedWeeksCount) external nonReentrant {
        LockedBalance memory lockedBalance = locked[msg.sender];
        require(lockedBalance.unlockTime > block.timestamp, "GameSchedualPool: EXPIRED_LOCK");
        require(_increasedWeeksCount > 0, "GameSchedualPool: INVALID_WEEKCOUNT");

        uint256 unlockTime = lockedBalance.unlockTime.add(_increasedWeeksCount * 1 weeks);
        uint256 weeksCount = lockedBalance.lockWeeks.add(_increasedWeeksCount);
        require(unlockTime <= block.timestamp + maxTime && lockWeights[weeksCount] > 0, "GameSchedualPool: INVALID_WEEKCOUNT");
        

        _update();
        _harvestRewardToken(msg.sender);

        scheduledUnlock[lockedBalance.unlockTime] = scheduledUnlock[lockedBalance.unlockTime].sub(lockedBalance.amount);
        scheduledUnlock[unlockTime] = scheduledUnlock[unlockTime].add(lockedBalance.amount);
        locked[msg.sender].rewardDebt = locked[msg.sender].amount.mul(lockWeights[weeksCount]).div(100).mul(accRewardPerShare).div(1e18);

        depositTotalPower = depositTotalPower.add(
            lockedBalance.amount.mul(
                lockWeights[weeksCount].sub(lockWeights[lockedBalance.lockWeeks])
            ).div(100)
        );
        locked[msg.sender].unlockTime = unlockTime;
        locked[msg.sender].lockWeeks = weeksCount;
        averageLockDur = (incrementalTotalSupply.mul(averageLockDur).div(10).add(lockedBalance.amount.mul(_increasedWeeksCount))).mul(10).div(incrementalTotalSupply);

        emit UnlockTimeIncreased(msg.sender, unlockTime, _increasedWeeksCount);
    }

    function withdraw() external nonReentrant {
        LockedBalance storage lockedBalance = locked[msg.sender];
        require(block.timestamp >= lockedBalance.unlockTime, "GameSchedualPool: NOT_UNLOCK");
        uint256 amount = uint256(lockedBalance.amount);

        _update();
        _harvestRewardToken(msg.sender);

        TransferHelper.safeTransfer(depositToken, msg.sender, amount);

        depositTokenSupply = depositTokenSupply.sub(amount);
        depositTotalPower = depositTotalPower.sub(
            lockedBalance.amount.mul(lockWeights[lockedBalance.lockWeeks]).div(100)
        );

        lockedBalance.unlockTime = 0;
        lockedBalance.amount = 0;
        lockedBalance.rewardDebt = 0;

        emit Withdraw(msg.sender, amount);
    }

    function harvest(address _to) external nonReentrant {
        _update();
        uint256 amount = _harvestRewardToken(_to);
        emit Harvest(msg.sender, _to, amount);
    }

    function _safeTokenTransfer(address _token, address _to, uint256 _amount) internal returns (uint256) {
        uint256 tokenBal = IShareToken(_token).balanceOf(address(this));
        if (_amount > 0) {
            if (tokenBal == 0) return 0;
            if (_amount > tokenBal) _amount = tokenBal;
            TransferHelper.safeTransfer(_token, _to, _amount);
        }
        return _amount;
    }

    function _harvestRewardToken(address _to) internal returns (uint256 amount) {
        LockedBalance storage lockedBalance = locked[msg.sender];
        uint256 pending = lockedBalance
            .amount
            .mul(lockWeights[lockedBalance.lockWeeks])
            .div(100)
            .mul(accRewardPerShare)
            .div(1e18)
            .sub(lockedBalance.rewardDebt);
        if (pending > 0) {
            if (harvestRate == 0) {
                amount = _safeTokenTransfer(rewardToken, _to, pending);
            } else {
                amount = _safeTokenTransfer(rewardToken, _to, pending.mul(harvestRate).div(100));
                uint256 lockAmount = _safeTokenTransfer(rewardToken, timeLock, pending.sub(amount));
                IGameTimeLock(timeLock).lock(_to, lockAmount);
            }
        }
        lockedBalance.rewardDebt = lockedBalance
            .amount
            .mul(lockWeights[lockedBalance.lockWeeks])
            .div(100)
            .mul(accRewardPerShare)
            .div(1e18);
        return amount;
    }

    function _update() internal {
        uint256 toBlock = block.number;
        if (toBlock <= lastBlock) {
            return;
        }
        if (depositTotalPower == 0) {
            lastBlock = toBlock;
            return;
        }

        (uint256 rewardAmount, ) = _mintRewardToken();
        accRewardPerShare = accRewardPerShare.add(
            rewardAmount.mul(1e18).div(depositTotalPower)
        );

        lastBlock = toBlock;
    }

    function _balanceOfAtTimestamp(address _account, uint256 _timestamp) internal view returns (uint256){
        require(_timestamp >= block.timestamp, "Must be current or future time");
        LockedBalance memory lockedBalance = locked[_account];
        if (_timestamp > lockedBalance.unlockTime) {
            return 0;
        }
        return (lockedBalance.amount.mul(lockedBalance.unlockTime - _timestamp)) / maxTime;
    }

    function _totalSupplyAtTimestamp(uint256 _timestamp) internal view returns (uint256) {
        uint256 weekCursor = (_timestamp / 1 weeks) * 1 weeks + 1 weeks;
        uint256 total = 0;
        for (; weekCursor <= _timestamp + maxTime; weekCursor += 1 weeks) {
            total = total.add(
                (scheduledUnlock[weekCursor].mul(weekCursor - _timestamp)) /
                    maxTime
            );
        }
        return total;
    }

    function _mintRewardToken() internal returns (uint256, uint256) {
        if (block.number <= lastBlock) {
            return (0, block.number);
        }

        uint256 multiplier = getMultiplier(lastBlock, block.number);
        uint256 rewardAmount = multiplier.mul(mintPerBlock);

        if (rewardAmount > IShareToken(rewardToken).funds(address(this))) {
            return (0, block.number);
        }

        IShareToken(rewardToken).mint(address(this), rewardAmount);
        return (rewardAmount, block.number);
    }

    function _updateAveLockDur(uint256 _amount, uint256 _weeksCount) internal {
        if (incrementalTotalSupply == 0) {
            incrementalTotalSupply = _amount;
            averageLockDur = _weeksCount.mul(10);
        } else {
            averageLockDur = (incrementalTotalSupply.mul(averageLockDur).div(10).add(_amount.mul(_weeksCount))).mul(10).div(incrementalTotalSupply.add(_amount));
            incrementalTotalSupply = incrementalTotalSupply.add(_amount);
        }
    }
}