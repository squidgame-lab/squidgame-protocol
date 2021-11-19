// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

import './libraries/SafeMath.sol';
import './libraries/EnumerableSet.sol';
import './libraries/TransferHelper.sol';
import './modules/ReentrancyGuard.sol';
import './modules/Configable.sol';
import './modules/Initializable.sol';

contract GameTimeLock is Configable, ReentrancyGuard, Initializable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    
    struct Lock {
        uint256 lockedAmount;
        uint256 startBlockNum;
        uint256 accReleasedPerBlock;
        uint256 debt;
    }

    mapping(address => Lock) public userLocked;
    mapping(address => bool) public farms;
    uint256 public duration; // block number
    uint256 public lockTotalSupply;
    address public lockToken;

    modifier onlyFarms() {
        require(farms[msg.sender], 'GameTimeLock: NOT_FARMS');
        _;
    }

    event SetLockToken(address indexed user, address oldOne, address newOne);
    event CreateLock(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);

    function initialize(address _lockToken, uint256 _duration) external initializer {
        require(_lockToken != address(0), 'GameTimeLock: INVALID_TOKEN');
        require(_duration > 0, 'GameTimeLock: INVALID_DURATION');
        owner = msg.sender;
        lockToken = _lockToken;
        duration = _duration;
    }

    function setFarmList(address[] calldata _farms) external onlyAdmin {
        require(_farms.length != 0, 'GameTimeLock: INVALID_FARMS');
        for (uint256 i = 0; i < _farms.length; i++) {
            farms[_farms[i]] = true;
        }
    }

    function disableFarm(address _farm) external onlyAdmin {
        farms[_farm] = false;
    }

    function setLockToken(address _lockToken) external onlyAdmin {
        require(_lockToken != lockToken, 'GameTimeLock: NO_CHANGE');
        emit SetLockToken(msg.sender, lockToken, _lockToken);
        lockToken = _lockToken;
    }

    function lock(address _account, uint256 _amount) external onlyFarms nonReentrant {
        require(_account != address(0), 'GameTimeLock: INVALID_ACCOUNT');
        require(_amount > 0, 'GameTimeLock: INVALID_AMOUNT');

        Lock memory lockInfo = userLocked[_account];
        if (lockInfo.lockedAmount == 0) {
            userLocked[_account] = Lock({
                lockedAmount: _amount,
                startBlockNum: block.number,
                accReleasedPerBlock: _amount.div(duration),
                debt: 0
            });
        } else {
            _claim(_account);
            uint256 balance = userLocked[_account].lockedAmount.sub(userLocked[_account].debt);
            userLocked[_account].lockedAmount = balance.add(_amount);
            userLocked[_account].startBlockNum = block.number;
            userLocked[_account].accReleasedPerBlock = userLocked[_account].lockedAmount.div(duration);
            userLocked[_account].debt = 0;
        }

        lockTotalSupply = lockTotalSupply.add(_amount);

        emit CreateLock(_account, _amount);
    }

    function claim() external {
        uint256 pendingAmount = _claim(msg.sender);
        emit Claim(msg.sender, pendingAmount);
    }

    function getPendingAmount(address _account) public view returns (uint256 _amount) {
        Lock memory lockInfo = userLocked[_account];
        if (block.number > lockInfo.startBlockNum.add(duration)) {
            return lockInfo.lockedAmount.sub(lockInfo.debt);
        }
        _amount = block.number.sub(lockInfo.startBlockNum).mul(lockInfo.accReleasedPerBlock).sub(lockInfo.debt);
        return _amount;
    }

    function getLockInfo(address _account) external view returns (uint256 lockedAmount, uint256 debt, uint256 accReleasedPerBlock) {
        return (
            userLocked[_account].lockedAmount,
            userLocked[_account].debt,
            userLocked[_account].accReleasedPerBlock
        );
    } 

    function _claim(address _account) internal returns (uint256 pendingAmount) {
        pendingAmount = getPendingAmount(_account);
        if (pendingAmount == 0) return pendingAmount;
        TransferHelper.safeTransfer(lockToken, _account, pendingAmount);
        userLocked[_account].debt = userLocked[_account].debt.add(pendingAmount);
        lockTotalSupply = lockTotalSupply.sub(pendingAmount);
    }
}