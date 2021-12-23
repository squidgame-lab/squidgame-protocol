// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

import './interfaces/IERC20.sol';
import './modules/Configable.sol';
import './modules/WhiteList.sol';
import './libraries/SafeMath.sol';
import './libraries/Strings.sol';
import "./libraries/Base64.sol";
import './libraries/TransferHelper.sol';
import './libraries/EnumerableSet.sol';
import './ERC721/extensions/ERC721Enumerable.sol';

contract GameBetTicket is ERC721Enumerable, Configable, WhiteList {
    using Strings for uint256;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    string public baseURI;
    string public imgSuffix;
    uint256 public minId;
    uint256 public maxId;

    event NonFungibleTokenRecovery(address indexed token, uint256 tokenId);
    event TokenRecovery(address indexed token, uint256 amount);

    constructor(string memory _name, string memory _symbol, uint256 _minId, uint _maxId, string memory _baseURI, string memory _imgSuffix) public {
        require(_maxId > _minId, 'GameBetTicket: Invalid max supply');
        owner = msg.sender;
        name = _name;
        symbol = _symbol;
        minId = _minId;
        maxId = _maxId;
        _setUriInfo(_baseURI, _imgSuffix);
    }

    function setWhiteList(address _addr, bool _value) external override onlyDev {
        _setWhiteList(_addr, _value);
    }
        
    function setWhiteLists(address[] calldata _addrs, bool[] calldata _values) external override onlyDev {
        require(_addrs.length == _values.length, 'GameBetTicket: Invalid param');
        for(uint i; i<_addrs.length; i++) {
            _setWhiteList(_addrs[i], _values[i]);
        }
    }

    function _setUriInfo(string memory _baseURI, string memory _imgSuffix) internal {
        baseURI = _baseURI;
        imgSuffix = _imgSuffix;
    } 

    function setUriInfo(string memory _baseURI, string memory _imgSuffix) external onlyDev {
        _setUriInfo(_baseURI, _imgSuffix);
    }

    function recoverNonFungibleToken(address _token, uint256 _tokenId) external onlyDev {
        IERC721(_token).transferFrom(address(this), address(msg.sender), _tokenId);
        emit NonFungibleTokenRecovery(_token, _tokenId);
    }

    function recoverToken(address _token) external onlyDev {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance != 0, "Operations: Cannot recover zero balance");
        TransferHelper.safeTransfer(_token, address(msg.sender), balance);
        emit TokenRecovery(_token, balance);
    }

    function tokensOfOwnerBySize(address user, uint256 cursor, uint256 size) external view returns (uint256[] memory, uint256) {
        uint256 length = size;
        if (length > balanceOf(user) - cursor) {
            length = balanceOf(user) - cursor;
        }
        uint256[] memory values = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = tokenOfOwnerByIndex(user, cursor + i);
        }
        return (values, cursor + length);
    }

    function imgURI(uint256 _tokenId) public view returns (string memory) {
        return string(abi.encodePacked(baseURI, _tokenId.toString(), imgSuffix));
    }

    function tokenURI(uint256 _tokenId) override public view returns (string memory) {
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "', name, ' #', _tokenId.toString(), '", "description": "', symbol, '", "image": "', imgURI(_tokenId), '"}'))));
        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    function mint(address _to, uint256 _tokenId) public onlyWhiteList {
        require(_tokenId >= minId && _tokenId <= maxId, "GameBetTicket: TokenId invalid");
        _mint(_to, _tokenId);
    }

    function mint(address[] memory _users, uint256[] memory _tokenIds) public onlyWhiteList {
        require(_users.length == _tokenIds.length, "GameBetTicket: Invalid args length");
        for (uint i = 0; i < _users.length; i++) {
            mint(_users[i], _tokenIds[i]);
        }
    }
}