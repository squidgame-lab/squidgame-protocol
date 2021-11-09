// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

import './interfaces/IShareToken.sol';
import './libraries/EnumerableSet.sol';
import './libraries/SafeMath.sol';
import './modules/ReentrancyGuard.sol';
import './modules/Initializable.sol';
import './modules/Configable.sol';

contract GameAirdrop is Configable, ReentrancyGuard, Initializable {
    using SafeMath for uint;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public token;
    uint public total;
    uint public balance;
    uint public startTime;
    uint public endTime;
    
    mapping (address => uint) public allowanceList;
    EnumerableSet.AddressSet claimedUser;

    event SetToken(address indexed admin, address oldOne, address newOne);
    event SetTotal(address indexed admin, uint oldOne, uint newOne);
    event SetTime(address indexed admin, uint oldStart, uint oldEnd, uint newStart, uint newEnd);
    event Claim(address indexed user, uint amount);

    modifier check(address _user) {
        require(block.timestamp >= startTime && block.timestamp <= endTime, 'GameAirdrop: WRONG_TIME');
        require(!claimedUser.contains(_user), 'GameAirdrop: DUPLICATION_CLAIM');
        require(IShareToken(token).take() >= balance && balance > 0, 'GameAirdrop: INSUFFICIENT_BALANCE');
        _;
    }

    function initialize(address _token, uint _total, uint _startTime, uint _endTime) external initializer {
        require(_token != address(0), 'GameAirdrop: INVALID_ADDRESS');
        require(_startTime < _endTime && block.timestamp < _endTime, 'GameAirdrop: INVALID_DATE');
        owner = msg.sender;
        (token, total, balance, startTime, endTime) = (_token, _total, _total, _startTime, _endTime);
    }

    function claimedCount() external view returns(uint count) {
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

    function setTotal(uint _total) external onlyAdmin {
        require(total != _total, 'GameAirdrop: NO_CHANGE');
        require(balance <= _total, 'GameAirdrop: LESS_THAN_BALANCE');
        emit SetTotal(msg.sender, total, _total);
        total = _total;
    }

    function setTime(uint _startTime, uint _endTime) external onlyAdmin {
        require(_startTime < _endTime && block.timestamp < _endTime, 'GameAirdrop: INVALID_DATE');
        emit SetTime(msg.sender, startTime, endTime, _startTime, _endTime);
        startTime = _startTime;
        endTime = _endTime;
    }

    function batchSetAllowanceList(address[] calldata _users, uint[] calldata _values) external onlyAdmin {
        require(_users.length == _values.length, 'GameAirdrop: INVALID_PARAMS');
        for (uint i=0; i < _users.length; i++){
            setAllowanceList(_users[i], _values[i]);
        }
    }

    function batchSetAllowanceListSame(address[] calldata _users, uint _value) external onlyAdmin {
        for (uint i=0; i < _users.length; i++){
            setAllowanceList(_users[i], _value);
        }
    }
    
    function setAllowanceList(address _user, uint _value) public onlyAdmin {
        allowanceList[_user] = _value;
    }

    function claim() external check(msg.sender) {
        require(allowanceList[msg.sender] > 0, 'GameAirdrop: INSUFFICIENT_ALLOWANCE');
        uint amount = balance > allowanceList[msg.sender] ? allowanceList[msg.sender] : balance;
        IShareToken(token).mint(msg.sender, amount);
        claimedUser.add(msg.sender);
        balance = balance.sub(amount);
        emit Claim(msg.sender, amount);   
    }
}
