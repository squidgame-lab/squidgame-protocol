// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

import "./interfaces/IERC20.sol";
import './interfaces/IShareToken.sol';
import "./interfaces/IGameTimeLock.sol";
import './libraries/SafeMath.sol';
import './libraries/TransferHelper.sol';
import './modules/Configable.sol';
import "./modules/ReentrancyGuard.sol";
import './modules/Initializable.sol';
import './modules/Pausable.sol';


// Have fun reading it. Hopefully it's bug-free. God bless.
contract GameFarm is Pausable, Configable, ReentrancyGuard, Initializable {
    using SafeMath for uint;

    // Info of each user.
    struct UserInfo {
        uint amount;         // How many tokens the user has provided.
        uint rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of RewardTokens
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRewardPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardPerShare` (and `lastBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.　
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        address depositToken;           // Address of token contract.
        uint allocPoint;       // How many allocation points assigned to this pool. RewardTokens to distribute per block.
        uint lastBlock;  // Last block number that RewardTokens distribution occurs.
        uint accRewardPerShare;   // Accumulated RewardTokens per share, times 1e18. See below.
        uint depositTokenSupply;
        bool paused;
    }

    uint public constant version = 1;

    // The reward TOKEN!
    address public rewardToken;
    
    // reward tokens created per block.
    uint public mintPerBlock;
    // Bonus muliplier for early rewardToken makers.
    uint public constant BONUS_MULTIPLIER = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    mapping(address => bool) public poolExistence;
    // Info of each user that stakes tokens.
    mapping(uint => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint;
    // The block number when reward token mining starts.
    uint public startBlock;
    address public timeLock;
    uint256 public harvestRate;

    event Deposit(address indexed user, address indexed to, uint indexed pid, uint amount);
    event Withdraw(address indexed user, address indexed to, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, address indexed to, uint indexed pid, uint amount);
    event SetEmissionRate(address indexed user, uint mintPerBlock);
    event SetHarvestRate(address indexed account, uint256 oldOne, uint256 newOne);
    event SetTimeLock(address indexed account, address oldOne, address newOne);

    modifier nonDuplicated(address _depositToken) {
        require(poolExistence[_depositToken] == false, "GameFarm: DUPLICATED");
        _;
    }

    modifier validatePoolByPid(uint _pid) {
        require (_pid < poolInfo.length , "GameFarm: POOL_NOT_EXIST");
        _;
    }

    function initialize(
        address _rewardToken,
        uint256 _mintPerBlock,
        uint256 _startBlock,
        uint256 _harvestRate,
        address _timeLock
    ) external initializer {
        require(_rewardToken != address(0), 'GameFarm: INVALID_ADDRESS');
        owner = msg.sender;
        rewardToken = _rewardToken;
        mintPerBlock = _mintPerBlock;
        startBlock = _startBlock;
        harvestRate = _harvestRate;
        timeLock = _timeLock;
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    function pause() public onlyManager whenNotPaused {
        _pause();
    }

    function unpause() public onlyManager whenPaused {
        _unpause();
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(bool _withUpdate, uint _allocPoint, address _depositToken) public onlyDev nonDuplicated(_depositToken) {
        if (_withUpdate) massUpdatePools(); 
        uint lastBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_depositToken] = true;
        poolInfo.push(PoolInfo({
            depositToken : _depositToken,
            allocPoint : _allocPoint,
            lastBlock : lastBlock,
            accRewardPerShare : 0,
            depositTokenSupply: 0,
            paused: false
        }));
    }

    function batchAdd(bool _withUpdate, uint[] memory _allocPoints, address[] memory _depositTokens) external onlyDev {
        require(_allocPoints.length == _depositTokens.length, 'GameFarm: INVALID_PARAMS');
        if (_withUpdate) massUpdatePools();
        for(uint i; i<_allocPoints.length; i++) {
            add(false, _allocPoints[i], _depositTokens[i]);
        }
    }

    function set(bool _withUpdate, uint _pid, uint _allocPoint, bool _paused) external validatePoolByPid(_pid) onlyManager {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].paused = _paused;
    }

    function batchSetAllocPoint(uint[] memory _pids, uint[] memory _allocPoints) external onlyManager {
        require(_pids.length == _allocPoints.length, 'GameFarm: INVALID_PARAMS');
        massUpdatePools();
        for (uint i; i<_pids.length; i++) {
            totalAllocPoint = totalAllocPoint.sub(poolInfo[_pids[i]].allocPoint).add(_allocPoints[i]);
            poolInfo[_pids[i]].allocPoint = _allocPoints[i];
        }
    }

    function batchSetPaused(uint[] memory _pids, bool[] memory _pauseds) external onlyManager {
        require(_pids.length == _pauseds.length, 'GameFarm: INVALID_PARAMS');
        for (uint i; i<_pids.length; i++) {
            poolInfo[_pids[i]].paused = _pauseds[i];
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint _from, uint _to) public pure returns (uint) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    function getToBlock() public view returns (uint) {
        return block.number;
    }

    function pendingRewardInfo(uint _pid) public view validatePoolByPid(_pid) returns (uint, uint) {
        PoolInfo storage pool = poolInfo[_pid];
        if (getToBlock() > pool.lastBlock && totalAllocPoint > 0) {
            uint multiplier = getMultiplier(pool.lastBlock, getToBlock());
            uint reward = multiplier.mul(mintPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            return (reward, block.number);
        }
        return (0, block.number);
    }

    // View function to see pending RewardTokens on frontend.
    function pendingReward(uint _pid, address _user) external view validatePoolByPid(_pid) returns (uint) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint accRewardPerShare = pool.accRewardPerShare;
        if (block.number > pool.lastBlock && pool.depositTokenSupply != 0) {
            uint multiplier = getMultiplier(pool.lastBlock, block.number);
            uint reward = multiplier.mul(mintPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(reward.mul(1e18).div(pool.depositTokenSupply));
        }
        return user.amount.mul(accRewardPerShare).div(1e18).sub(user.rewardDebt);
    }
    
    function _mintRewardToken(uint _pid) internal returns (uint, uint) {
        (uint reward,) = pendingRewardInfo(_pid);
        if(reward > IShareToken(rewardToken).funds(address(this))) {
            return (0, block.number);
        }
        IShareToken(rewardToken).mint(address(this), reward);
        return (reward, block.number);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        uint toBlock = getToBlock();
        if (toBlock <= pool.lastBlock) {
            return;
        }
        if (pool.depositTokenSupply == 0 || pool.allocPoint == 0) {
            pool.lastBlock = toBlock;
            return;
        }
        
        (uint reward,) = _mintRewardToken(_pid);
        pool.accRewardPerShare = pool.accRewardPerShare.add(reward.mul(1e18).div(pool.depositTokenSupply));

        pool.lastBlock = toBlock;
    }

    // Deposit tokens to GameFarm for reward allocation.
    function deposit(uint _pid, uint _amount, address _to) external validatePoolByPid(_pid) whenNotPaused nonReentrant returns(uint) {
        require(_amount > 0, 'GameFarm: INVALID_AMOUNT');
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.paused == false, "GameFarm: POOL_PAUSED");
        UserInfo storage user = userInfo[_pid][_to];
        updatePool(_pid);
        _harvestRewardToken(_pid, _to);
        IERC20(pool.depositToken).transferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        pool.depositTokenSupply  = pool.depositTokenSupply.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Deposit(msg.sender, _to, _pid, _amount);
        return _amount;
    }

    // Withdraw tokens from GameFarm.
    function withdraw(uint _pid, uint _amount, address _to) external validatePoolByPid(_pid) whenNotPaused nonReentrant returns(uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(pool.paused == false, "GameFarm: POOL_PAUSED");
        require(user.amount >= _amount, "GameFarm: INSUFFICIENT_AMOUNT");
        updatePool(_pid);
        _harvestRewardToken(_pid, _to);
       
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.depositTokenSupply = pool.depositTokenSupply.sub(_amount);
            TransferHelper.safeTransfer(pool.depositToken, _to, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Withdraw(msg.sender, _to, _pid, _amount);
        return _amount;
    }

    function _harvestRewardToken(uint _pid, address _to) internal returns(uint amount) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            if (harvestRate == 0) {
                amount = safeTokenTransfer(rewardToken, _to, pending);
            } else {
                amount = safeTokenTransfer(rewardToken, _to, pending.mul(harvestRate).div(100));
                uint256 lockAmount = safeTokenTransfer(rewardToken, timeLock, pending.sub(amount));
                IGameTimeLock(timeLock).lock(_to, lockAmount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        return amount;
    }

    function harvest(uint _pid, address _to) external validatePoolByPid(_pid) whenNotPaused nonReentrant  returns (uint reward) {
        require(poolInfo[_pid].paused == false, "GameFarm: POOL_PAUSED");
        updatePool(_pid);
        reward = _harvestRewardToken(_pid, _to);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint _pid, address _to) external validatePoolByPid(_pid) nonReentrant returns(uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint amount = user.amount;
        require(amount > 0, 'GameFarm: INSUFFICIENT_BALANCE');
        user.amount = 0;
        user.rewardDebt = 0;
        pool.depositTokenSupply = pool.depositTokenSupply.sub(amount);
        TransferHelper.safeTransfer(pool.depositToken, _to, amount);
        emit EmergencyWithdraw(msg.sender, _to, _pid, amount);
        return amount;
    }

    // Safe Token transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeTokenTransfer(address _token, address _to, uint _amount) internal returns(uint) {
        uint tokenBal = IERC20(_token).balanceOf(address(this));
        if(_amount >0) {
            if(tokenBal == 0) {
                return 0;
            }
            if (_amount > tokenBal) {
                _amount = tokenBal;
            }
            TransferHelper.safeTransfer(_token, _to, _amount);
        }
        return _amount;
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

    //reward has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function setEmissionRate(uint _mintPerBlock) external onlyDev {
        massUpdatePools();
        mintPerBlock = _mintPerBlock;
        emit SetEmissionRate(msg.sender, _mintPerBlock);
    }
}
