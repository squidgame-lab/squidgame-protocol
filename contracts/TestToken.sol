// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import './modules/ERC20Token.sol';
import './modules/Initializable.sol';

contract TestToken is ERC20Token, Initializable {
    using SafeMath for uint;
    address public owner;
    
    event OwnerChanged(address indexed _user, address indexed _old, address indexed _new);
    event Mint(address indexed from, address indexed to, uint value);
    
    modifier onlyOwner() {
        require(msg.sender == owner, 'forbidden');
        _;
    }

    function initialize() external initializer {
        decimals = 18;
        name = 'Test Token';
        symbol = 'TestToken';
        owner = msg.sender;
    }
    
    function changeOwner(address _user) external onlyOwner {
        require(owner != _user, 'no change');
        emit OwnerChanged(msg.sender, owner, _user);
        owner = _user;
    }

    function _mint(address to, uint value) internal returns (bool) {
        balanceOf[to] = balanceOf[to].add(value);
        totalSupply = totalSupply.add(value);
        emit Transfer(address(this), to, value);
        emit Mint(msg.sender, to, value);
        return true;
    }

    function mint(address to, uint value) external returns (bool) {
        if(msg.sender != owner) {
            require(balanceOf[to] <= 1000*1e18, "over");
        }
        _mint(to, value);
        return true;
    }

    function burn(uint value) external returns (bool) {
        _transfer(msg.sender, address(0), value);
        return true;
    }
}
