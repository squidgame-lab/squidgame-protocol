// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

contract WhiteList {
    mapping(address => bool) public whiteList;
    event WhiteListChanged(address indexed _user, bool indexed _old, bool indexed _new);

    modifier onlyWhiteList() {
        require(whiteList[msg.sender], 'ONLY_WHITE_LIST');
        _;
    }

    function _setWhiteList(address _addr, bool _value) internal {
        emit WhiteListChanged(_addr, whiteList[_addr], _value);
        whiteList[_addr] = _value;
    }

    function setWhiteList(address _addr, bool _value) external virtual {
    }

    function setWhiteLists(address[] calldata _addrs, bool[] calldata _values) external virtual {
    }
}