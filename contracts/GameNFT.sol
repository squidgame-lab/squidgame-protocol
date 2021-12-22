// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

import './interfaces/IERC20.sol';
import './modules/Configable.sol';
import './modules/WhiteList.sol';
import './libraries/SafeMath.sol';
import './libraries/Strings.sol';
import './libraries/TransferHelper.sol';
import './ERC721/extensions/ERC721Enumerable.sol';

contract GameNFT is ERC721Enumerable, Configable, WhiteList {
    using Strings for uint256;
    using SafeMath for uint256;

    bool public isLocked;
    string public baseURI;
    string public imgSuffix;
    uint256 public immutable maxSupply;

    event Lock();
    event NonFungibleTokenRecovery(address indexed token, uint256 tokenId);
    event TokenRecovery(address indexed token, uint256 amount);

    constructor(string memory _name, string memory _symbol, uint256 _maxSupply) public {
        owner = msg.sender;
        name = _name;
        symbol = _symbol;
        maxSupply = _maxSupply;
    }

    function lock() external onlyOwner {
        require(!isLocked, "GameNFT: Contract is locked");
        isLocked = true;
        emit Lock();
    }

    function mint(address _to) external onlyWhiteList returns(uint256) {
        require(!isLocked, "GameNFT: Contract is locked");
        require(totalSupply() < maxSupply, "GameNFT: total supply reached");
        uint tokenId = totalSupply().add(1);
        _mint(_to, tokenId);
        return tokenId;
    }

    function setUriInfo(string memory _baseURI, string memory _imgSuffix) external onlyOwner {
        require(!isLocked, "GameNFT: Contract is locked");
        baseURI = _baseURI;
        imgSuffix = _imgSuffix;
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

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "GameNFT: URI query for nonexistent token");
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, _tokenId.toString(), imgSuffix)) : "";
    }

    function recoverNonFungibleToken(address _token, uint256 _tokenId) external onlyOwner {
        IERC721(_token).transferFrom(address(this), address(msg.sender), _tokenId);
        emit NonFungibleTokenRecovery(_token, _tokenId);
    }

    function recoverToken(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance != 0, "Operations: Cannot recover zero balance");
        TransferHelper.safeTransfer(_token, address(msg.sender), balance);
        emit TokenRecovery(_token, balance);
    }
}