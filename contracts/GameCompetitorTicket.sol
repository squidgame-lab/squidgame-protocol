// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;
pragma experimental ABIEncoderV2;

import "./libraries/Base64.sol";

import "./ERC721/extensions/ERC721Enumerable.sol";
import './modules/ReentrancyGuard.sol';
import './modules/Initializable.sol';
import './modules/Configable.sol';
import './modules/WhiteList.sol';

contract GameCompetitorTicket is Configable, WhiteList, ERC721Enumerable, ReentrancyGuard, Initializable {
    string public baseURI;
    string public imgSuffix;

    uint256 public maxTotal;
    uint256 public expiredTime; // block number

    uint256 public claimBeginId;
    uint256 public claimedId;

    function initialize(uint256 _maxTotal, uint256 _claimBeginId, uint256 _expiredTime, string memory _baseURI, string memory _imgSuffix, string calldata _name, string calldata _symbol) external initializer {
        _configure(_maxTotal, _claimBeginId, _expiredTime, _baseURI, _imgSuffix);
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
    }

    function _configure(uint256 _maxTotal, uint256 _claimBeginId, uint256 _expiredTime, string memory _baseURI, string memory _imgSuffix) internal {
        maxTotal = maxTotal;
        claimBeginId = _claimBeginId;
        expiredTime = _expiredTime;
        baseURI = _baseURI;
        imgSuffix = _imgSuffix;
    }

    function configure(uint256 _maxTotal, uint256 _claimBeginId, uint256 _expiredTime, string memory _baseURI, string memory _imgSuffix) external onlyDev {
        _configure(_maxTotal, _claimBeginId, _expiredTime, _baseURI, _imgSuffix);
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

    function imgURI(uint256 _tokenId) public view returns (string memory) {
        return string(abi.encodePacked(baseURI, toString(_tokenId), imgSuffix));
    }

    function tokenURI(uint256 _tokenId) override public view returns (string memory) {
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "', name, ' #', toString(_tokenId), '", "description": "', symbol, '", "image": "', imgURI(_tokenId), '"}'))));
        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    function _claim(address _to, uint256 _tokenId) internal returns (uint256) {
        require(_tokenId > 0, 'GCT: zero');
        require(_tokenId <= maxTotal, 'GCT: over');
        require(ownerOf(_tokenId) == address(0), 'GCT: claimed');
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

    function mint(address _to) external onlyWhiteList returns (uint256) {
        require(claimedId < maxTotal, 'GCT: done');
        if(claimedId == 0)  {
            claimedId = claimBeginId;
        } else {
            claimedId++;
        }
        
        _claim(_to, claimedId); 
        return claimedId;
    }

    function mint(address _to) external onlyWhiteList returns (uint256) {
        require(claimedId < maxTotal, 'GCT: done');
        if(claimedId == 0)  {
            claimedId = claimBeginId;
        } else {
            claimedId++;
        }
        
        _claim(_to, claimedId); 
        return claimedId;
    }

    function mint(address _to, uint256 _tokenId) public onlyWhiteList returns (uint256) {
        require(_tokenId < claimBeginId, 'GCT: must be >= claimBeginId');
        _claim(_to, claimedId); 
        return claimedId;
    }

    function mint(address _to, uint256 _beginId, uint256 _endId) external onlyWhiteList {
        require(_beginId <= _endId, 'GCT: invalid param');
        for(uint256 i=_beginId; i<=_endId; i++) {
            mint(_to, i);
        }
    }

    function mint(address[] calldata _users, uint256[] calldata _tokenIds) external onlyWhiteList returns (uint256) {
        require(_users.length == _tokenIds.length, 'GCT: invalid param');
        for(uint256 i; i<_users.length; i++) {
            mint(_users[i], _tokenIds[i]);
        }
    }
}
