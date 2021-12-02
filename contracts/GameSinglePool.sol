// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

import "./interfaces/IERC20.sol";
import './libraries/SafeMath.sol';
import './libraries/TransferHelper.sol';
import './modules/Configable.sol';
import "./modules/ReentrancyGuard.sol";
import './modules/Initializable.sol';

contract GameSinglePool is Configable, ReentrancyGuard, Initializable {
    using SafeMath for uint256;

    struct UserInfo {
        uint256 amount;     
        uint256 unlockTime;
        uint256 rewardDebt;
    }
    mapping(address => UserInfo) public userInfo;

    uint256 public constant BONUS_MULTIPLIER = 1;
    uint256 public lastBlock;
    uint256 public accRewardPerShare;
    uint256 public depositTokenSupply;
    
    address public assetsAccount;
    address public depositToken;
    address public rewardToken;
    uint256 public startBlock;
    uint256 public mintPerBlock;
    uint256 public lockWeekCount;
    uint256 public lockDuration;

    event SetEmissionRate(address indexed user, uint256 mintPerBlock);
    event SetAssetsAccount(address indexed user, address account);
    event SetLockDuration(address indexed user, uint256 lockDuration);
    event Deposit(address indexed user, address indexed to, uint256 amount, uint256 unlockTime);
    event Withdraw(address indexed user, address indexed to, uint256 amount);
    event Harvest(address indexed user, address indexed to, uint256 amount);

    function initialize(
        address _assetsAccount,
        address _depositToken,
        address _rewardToken,
        uint256 _startBlock,
        uint256 _mintPerBlock,
        uint256 _lockDuration
    ) external initializer {
        require(_assetsAccount !=address(0) && _depositToken != address(0) && _rewardToken != address(0), 'GameSinglePool: INVALID_ADDRESS');
        owner = msg.sender;
        assetsAccount = _assetsAccount;
        depositToken = _depositToken;
        rewardToken = _rewardToken;
        mintPerBlock = _mintPerBlock;
        lastBlock = block.number > _startBlock ? block.number : _startBlock;
        lockDuration = _lockDuration;
    }

    function setEmissionRate(uint256 _mintPerBlock) external onlyDev {
        _updatePool();
        mintPerBlock = _mintPerBlock;
        emit SetEmissionRate(msg.sender, _mintPerBlock);
    }

    function setAssetsAccount(address _account) external onlyDev {
        require(_account != address(0), 'GameSinglePool: INVALID_ACCOUNT');
        assetsAccount = _account;
        emit SetAssetsAccount(msg.sender, _account);
    }

    function setLockDuration(uint256 _lockDuration) external onlyDev {
        lockDuration = _lockDuration;
        emit SetLockDuration(msg.sender, _lockDuration);
    }

    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    function getToBlock() public view returns (uint256) {
        return block.number;
    }

    function pendingRewardInfo() public view returns (uint256, uint256) {
        if (getToBlock() > lastBlock) {
            uint256 multiplier = getMultiplier(lastBlock, getToBlock());
            uint256 reward = multiplier.mul(mintPerBlock);
            return (reward, block.number);
        }
        return (0, block.number);
    }

    function pendingReward(address _user) external view returns (uint256) {
        UserInfo memory user = userInfo[_user];
        uint256 accRewardPerShareTMP = accRewardPerShare;
        if (block.number > lastBlock && depositTokenSupply != 0) {
            uint256 multiplier = getMultiplier(lastBlock, block.number);
            uint256 rewardAmount = multiplier.mul(mintPerBlock);
            uint256 balance = IERC20(rewardToken).balanceOf(assetsAccount);
            rewardAmount = rewardAmount > balance ? balance : rewardAmount;
            accRewardPerShareTMP = accRewardPerShareTMP.add(rewardAmount.mul(1e18).div(depositTokenSupply));
        }
        return user.amount.mul(accRewardPerShareTMP).div(1e18).sub(user.rewardDebt);
    }
    
    function deposit(uint256 _amount, address _to) external nonReentrant returns(uint256) {
        require(_amount > 0, 'GameSinglePool: INVALID_AMOUNT');
        UserInfo storage user = userInfo[_to];
        _updatePool();
        _harvestRewardToken(_to);
        if (user.unlockTime <= block.timestamp && user.amount > 0) {   
            _withdraw(user.amount, _to);
        }
        TransferHelper.safeTransferFrom(depositToken, address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.unlockTime = block.timestamp.add(lockDuration);
        depositTokenSupply  = depositTokenSupply.add(_amount);
        user.rewardDebt = user.amount.mul(accRewardPerShare).div(1e18);
        emit Deposit(msg.sender, _to, _amount, user.unlockTime);
        return _amount;
    }

    function withdraw(uint256 _amount, address _to) public nonReentrant returns(uint256) {
        require(userInfo[msg.sender].unlockTime <= block.timestamp, "GameSinglePool: NOT_UNLOCKED");
        _updatePool();
        _harvestRewardToken(_to);
        _withdraw(_amount, _to);
        return _amount;
    }

    function harvest(address _to) external nonReentrant returns (uint256 reward) {
        _updatePool();
        reward = _harvestRewardToken(_to);
    }

    function _updatePool() internal {
        uint256 toBlock = getToBlock();
        if (toBlock <= lastBlock) {
            return;
        }
        if (depositTokenSupply == 0) {
            lastBlock = toBlock;
            return;
        }
        (uint256 reward,) = _mintRewardToken();
        accRewardPerShare = accRewardPerShare.add(reward.mul(1e18).div(depositTokenSupply));
        lastBlock = toBlock;
    }

    function _mintRewardToken() internal returns (uint256, uint256) {
        (uint256 rewardAmount,) = pendingRewardInfo();
        uint256 balance = IERC20(rewardToken).balanceOf(assetsAccount);
        rewardAmount = rewardAmount > balance ? balance : rewardAmount;
        if(rewardAmount > 0) {
            TransferHelper.safeTransferFrom(rewardToken, assetsAccount, address(this), rewardAmount);
        }
        return (rewardAmount, block.number);
    }

    function _withdraw(uint256 _amount, address _to) internal returns (uint256) {
        require(_amount > 0, "GameSinglePool: ZERO");
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "GameSinglePool: INSUFFICIENT_AMOUNT");
        user.amount = user.amount.sub(_amount);
        depositTokenSupply = depositTokenSupply.sub(_amount);
        TransferHelper.safeTransfer(depositToken, _to, _amount);
        user.rewardDebt = user.amount.mul(accRewardPerShare).div(1e18);
        emit Withdraw(msg.sender, _to, _amount);
    }

    function _harvestRewardToken(address _to) internal returns(uint256 amount) {
        UserInfo storage user = userInfo[msg.sender];
        uint256 pending = user.amount.mul(accRewardPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) amount = _safeTokenTransfer(rewardToken, _to, pending); 
        user.rewardDebt = user.amount.mul(accRewardPerShare).div(1e18);
        emit Harvest(msg.sender, _to, amount);
        return amount;
    }

    function _safeTokenTransfer(address _token, address _to, uint256 _amount) internal returns(uint256) {
        uint256 tokenBal = IERC20(_token).balanceOf(address(this));
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
}
