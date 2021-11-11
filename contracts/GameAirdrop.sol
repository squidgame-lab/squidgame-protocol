// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

import './interfaces/IShareToken.sol';
import './libraries/EnumerableSet.sol';
import './libraries/SafeMath.sol';
import './modules/ReentrancyGuard.sol';
import './modules/Initializable.sol';
import './modules/Configable.sol';

contract GameAirdrop is Configable, ReentrancyGuard, Initializable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public token;
    uint256 public total;
    uint256 public balance;
    uint256 public startTime;
    uint256 public endTime;
    
    mapping (address => uint256) public allowanceList;
    EnumerableSet.AddressSet claimedUser;

    event SetToken(address indexed admin, address oldOne, address newOne);
    event SetTotal(address indexed admin, uint256 oldOne, uint256 newOne);
    event SetTime(address indexed admin, uint256 oldStart, uint256 oldEnd, uint256 newStart, uint256 newEnd);
    event Claim(address indexed user, uint256 amount);

    modifier check(address _user) {
        require(block.timestamp >= startTime && block.timestamp <= endTime, 'GameAirdrop: WRONG_TIME');
        require(!claimedUser.contains(_user), 'GameAirdrop: DUPLICATION_CLAIM');
        require(IShareToken(token).take() >= balance && balance > 0, 'GameAirdrop: INSUFFICIENT_BALANCE');
        _;
    }

    function initialize(address _token, uint256 _total, uint256 _startTime, uint256 _endTime) external initializer {
        require(_token != address(0), 'GameAirdrop: INVALID_ADDRESS');
        require(_startTime < _endTime && block.timestamp < _endTime, 'GameAirdrop: INVALID_DATE');
        owner = msg.sender;
        (token, total, balance, startTime, endTime) = (_token, _total, _total, _startTime, _endTime);
    }

    function claimedCount() external view returns(uint256 count) {
        return claimedUser.length();
    }

    function claimed(address _user) external view returns(bool) {
        return claimedUser.contains(_user);
    }

    function setToken(address _token) external onlyAdmin {
        require(_token != address(0) && _token != token, 'GameAirdrop: INVALID_ADDRESS');
        emit SetToken(msg.sender, token, _token);
        token = _token;
    }

    function setTotal(uint256 _total) external onlyAdmin {
        require(total != _total, 'GameAirdrop: NO_CHANGE');
        if (total < _total) {
            balance = balance.add(_total.sub(total));   
        } else {
            uint256 subAmount = total.sub(_total);
            balance = subAmount >= balance ? 0 : balance.sub(subAmount);
        }
        emit SetTotal(msg.sender, total, _total);
        total = _total;
    }

    function setTime(uint256 _startTime, uint256 _endTime) external onlyAdmin {
        require(_startTime < _endTime && block.timestamp < _endTime, 'GameAirdrop: INVALID_DATE');
        emit SetTime(msg.sender, startTime, endTime, _startTime, _endTime);
        startTime = _startTime;
        endTime = _endTime;
    }

    function batchSetAllowanceList(address[] calldata _users, uint256[] calldata _values) external onlyAdmin {
        require(_users.length == _values.length, 'GameAirdrop: INVALID_PARAMS');
        for (uint256 i=0; i < _users.length; i++){
            setAllowanceList(_users[i], _values[i]);
        }
    }

    function batchSetAllowanceListSame(address[] calldata _users, uint256 _value) external onlyAdmin {
        for (uint256 i=0; i < _users.length; i++){
            setAllowanceList(_users[i], _value);
        }
    }
    
    function setAllowanceList(address _user, uint256 _value) public onlyAdmin {
        allowanceList[_user] = _value;
    }

    function claim() external check(msg.sender) {
        require(allowanceList[msg.sender] > 0, 'GameAirdrop: INSUFFICIENT_ALLOWANCE');
        uint256 amount = balance > allowanceList[msg.sender] ? allowanceList[msg.sender] : balance;
        IShareToken(token).mint(msg.sender, amount);
        claimedUser.add(msg.sender);
        balance = balance.sub(amount);
        emit Claim(msg.sender, amount);   
    }
}
