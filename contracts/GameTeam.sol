// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;
import './interfaces/IERC20.sol';
import './modules/Configable.sol';
import './modules/Initializable.sol';

contract GameTeam is Configable, Initializable {
    address public shareToken;
    address[] public users;
    mapping (address => uint) public rates;

    struct UserRate {
        address user;
        uint rate;
    }

    function initialize(address _shareToken) external initializer {
        owner = msg.sender;
        shareToken = _shareToken;
    }

    function setShareToken(address _shareToken) external onlyDev {
        shareToken = _shareToken;
    }

    function setRate(address[] calldata _users, uint[] calldata _values) external onlyManager {
        require(_users.length > 0  && _users.length == _values.length, 'invalid param');
        uint count = users.length;
        for(uint i; i<count; i++) {
            users.pop();
        }
        uint _total;
        for(uint i; i<_users.length; i++) {
            _total += _values[i];
            rates[_users[i]] = _values[i];
            users.push(_users[i]);
        }
        
        require(_total == 100, 'sum of rate is not 100');
    }

    function withdraw(address _shareToken, uint _amount) external {
        require(foundUser() || msg.sender == dev() || msg.sender == admin() || msg.sender == owner, "permission");
        uint balance = IERC20(_shareToken).balanceOf(address(this));
        if(_amount > balance) {
            _amount = balance;
        }
        require(_amount > 0, 'zero');
        for(uint i; i<users.length; i++) {
            uint v = _amount * rates[users[i]] / 100;
            if(v > 0) IERC20(_shareToken).transfer(users[i], v);
        }
    }

    function countUser() public view returns (uint) {
        return users.length;
    }

    function foundUser() public view returns (bool) {
        for(uint i; i<users.length; i++) {
            if(users[i] == msg.sender) return true;
        }
        return false;
    }

    function getUserRates() external view returns (UserRate[] memory list) {
        if(users.length == 0) return list;
        list = new UserRate[](users.length);
        for(uint i; i<users.length; i++) {
            list[i] = UserRate({
                user: users[i],
                rate: rates[users[i]]
            });
        }
    }

}
