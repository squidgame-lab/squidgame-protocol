// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;
pragma experimental ABIEncoderV2;

import "./libraries/Base64.sol";

import "./ERC721/extensions/ERC721Enumerable.sol";
import './modules/ReentrancyGuard.sol';
import './modules/Initializable.sol';
import './modules/GameHeroNotify.sol';
import './modules/Configable.sol';
import './modules/WhiteList.sol';

contract GameCompetitorTicket is Configable, WhiteList, ERC721Enumerable, ReentrancyGuard, Initializable {
    string public baseURI;
    string public imgSuffix;

    uint256 public maxTotal;
    uint256 public total;
    uint256 public expiredTime; // block number
    uint256 public maxGroupId;  // skip 0, start 1

    struc Group {
        uint256 id;
        uint256 beginId;
        uint256 endId;
        uint256 beginTime;
        uint256 endTime;
    }

    mapping(uint256 => Group) public groups;

    function initialize(uint256 _maxTotal, uint256 _maxGroupId, string calldata _name, string calldata _symbol) external initializer {
        maxTotal = maxTotal;
        maxGroupId = _maxGroupId;
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
    }
    
    function setWhiteList(address _addr, bool _value) external override onlyDev {
        _setWhiteList(_addr, _value);
    }
        
    function setWhiteLists(address[] calldata _addrs, bool[] calldata _values) external override onlyDev {
        require(_addrs.length == _values.length, 'GCT: invalid param');
        for(uint i; i<_addrs.length; i++) {
            _setWhiteList(_addrs[i], _values[i]);
        }
    }

    function setUriInfo(string memory _baseURI, string memory _imgSuffix) external onlyDev {
        baseURI = _baseURI;
        imgSuffix = _imgSuffix;
    }

    function setGroup(Group memory _group) public onlyManager {
        require(_group.id <= maxGroupId, 'GCT:: invalid id');
        require(_group.beginTime > block.number && _group.beginTime<=_group.endTime, 'GCT:: invalid time');
        groups[_group.id] = _group;
    }

    function setGroups(Group[] memory _groups) external onlyDev {
        groups = _groups;
    }

    function getGroup(uint256 _id) external view returns (Group memory) {
        require(_id <= maxGroupId, 'GCT:: invalid id');
        return groups[_id];
    }

    function getGroups() external view returns (Group[] memory result) {
        result = new Group[](maxGroupId+1);
        for(uint256 i; i<=maxGroupId; i++) {
            result[i] = groups[i];
        }
    }

    function imgURI(uint256 _tokenId) public view returns (string memory) {
        return string(abi.encodePacked(baseURI, toString(_tokenId), imgSuffix));
    }

    function tokenURI(uint256 _tokenId) override public view returns (string memory) {
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "', name, ' #', toString(_tokenId), '", "description": "', symbol, '", "image": "', imgURI(_tokenId), '"}'))));
        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    function _claim(address _to) internal returns (uint256) {
        total++;
        require(total <= maxTotal, 'GCT: over');
        uint256 _tokenId = total;
        _safeMint(_to, _tokenId);
        return _tokenId;
    }

    function burn(uint256 _tokenId) external {
        require(_isApprovedOrOwner(_msgSender(), _tokenId), "ERC721: transfer caller is not owner nor approved");
        _burn(_tokenId);
    }

    function toString(uint256 value) public pure returns (string memory) {
    // Inspired by OraclizeAPI's implementation - MIT license
    // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
