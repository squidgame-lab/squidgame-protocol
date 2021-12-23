// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;
pragma experimental ABIEncoderV2;

import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";
import './libraries/EnumerableSet.sol';
import './libraries/Rand.sol';
import './libraries/Signature.sol';
import "./modules/ReentrancyGuard.sol";
import "./modules/Configable.sol";
import "./modules/Initializable.sol";
import "./interfaces/IERC20.sol";

interface IGameNFT {
    function mint(address _to) external returns(uint256);
}

interface IGameBetTicket {
    function mint(address _to, uint256 _tokenId) external;
}

contract GameNFTMarket is Configable, ReentrancyGuard, Initializable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    struct Conf {
        address nft;
        address paymentToken;
        uint price;
        uint startTime;
        uint endTime;
        uint total;
        uint minId;
        uint maxId;
        bool isRand;
    }

    mapping(address => Conf) nft2conf;
    mapping(address => bool) nft2exist;
    mapping(address => uint) nft2balance;
    mapping(address => EnumerableSet.UintSet) nft2numPool;

    address public treasury;

    event SetConf(address user, address nft, address paymenToken, uint256 price, uint256 startTime, uint256 endTime, uint256 _total);
    event Buy(address user, address nft, address to, uint256[] tokenIds);

    receive() external payable {
    }

    function initialize(address _treasury) external initializer {
        owner = msg.sender;
        treasury = _treasury;
    }

    function getConf(address _nft) public view returns(Conf memory conf) {
        if(!nft2exist[_nft]) return conf;
        conf = nft2conf[_nft];
    }

    function getConfList(address[] calldata _nfts) external view returns(Conf[] memory confList) {
        confList = new Conf[](_nfts.length);
        for (uint i = 0; i < _nfts.length; i++) {
            confList[i] = getConf(_nfts[i]);
        }
    }

    function setConf(Conf memory _conf) public onlyDev {
        require(_conf.nft != address(0), 'GameNFTMarket: Invalid conf nft');
        require(_conf.total > 0 && _conf.maxId.sub(_conf.minId) == _conf.total, 'GameNFTMarket: Invalid conf total');
        require(_conf.startTime < _conf.endTime && _conf.endTime > block.timestamp, 'GameNFTMarket: Invalid conf time');
        
        if (!nft2exist[_conf.nft]) {
            nft2conf[_conf.nft] = _conf;
            nft2exist[_conf.nft] = true;
        } else {
            Conf memory conf = nft2conf[_conf.nft];
            require(conf.startTime > block.timestamp, 'GameNFTMarket: NFT is selling');
            nft2conf[_conf.nft] = _conf;
        }

        nft2balance[_conf.nft] = _conf.total;
        if (_conf.isRand) {
            _generateNumsPool(_conf.nft, _conf.minId, _conf.maxId);
        }

        emit SetConf(msg.sender, _conf.nft, _conf.paymentToken, _conf.price,  _conf.startTime,  _conf.endTime, _conf.total);
    }

    function batchSetConf(Conf[] calldata _confs) external onlyDev {
        require(_confs.length > 0, 'GNM: INVALID_ARG_LENGTH');
        for (uint256 i = 0; i < _confs.length; i++) {
            setConf(_confs[i]);
        }
    }

    function buy(address _nft, uint256 _amount, address _to) external payable returns(uint256[] memory tokenIds){
        require(nft2exist[_nft], 'GNM: Invalid nft addr');
        Conf memory conf = nft2conf[_nft];
        require(block.timestamp >= conf.startTime && block.timestamp < conf.endTime, 'GNM: Sell expired');
        require(_amount <= nft2balance[_nft] && _amount != 0, 'GNM: Invalid amount');

        uint256 value = _amount.mul(conf.price);
        if (conf.paymentToken == address(0)) {
            TransferHelper.safeTransferETH(treasury, value);
        } else {
            TransferHelper.safeTransferFrom(conf.paymentToken, msg.sender, treasury, value);
        }

        tokenIds = new uint256[](_amount);
        for (uint i = 0; i < _amount; i++) {
            uint256 tokenId = IGameNFT(conf.nft).mint(_to);
            tokenIds[i] = tokenId;
        }

        nft2balance[_nft] = nft2balance[_nft].sub(_amount);

        emit Buy(msg.sender, _nft, _to, tokenIds);
    }

    function buyRand(address _nft, address _to, uint256[] memory _seeds, bytes memory _signature) external payable returns(uint256[] memory tokenIds){
        require(nft2exist[_nft], 'GNM: Invalid nft addr');
        Conf memory conf = nft2conf[_nft];
        require(block.timestamp >= conf.startTime && block.timestamp < conf.endTime, 'GNM: Sell expired');
        uint256 amount = _seeds.length;
        require(amount <= nft2balance[_nft], 'GNM: Invalid amount');

        uint256 value = amount.mul(conf.price);
        if (conf.paymentToken == address(0)) {
            TransferHelper.safeTransferETH(treasury, value);
        } else {
            TransferHelper.safeTransferFrom(conf.paymentToken, msg.sender, treasury, value);
        }

        tokenIds = new uint256[](amount);
        for (uint i = 0; i < amount; i++) {
            uint256 tokenId = _getNumFromPool(_nft, _seeds[i]);
            IGameBetTicket(_nft).mint(_to, tokenId);
            tokenIds[i] = tokenId;
        }

        nft2balance[_nft] = nft2balance[_nft].sub(amount);

        emit Buy(msg.sender, _nft, _to, tokenIds);
    }

    function verify(address _signer, uint256[] memory _seeds, bytes memory _signatures) public view returns (bool) {
        bytes32 message = keccak256(abi.encodePacked(_seeds, address(this)));
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        address[] memory signList = Signature.recoverAddresses(hash, _signatures);
        return signList[0] == _signer;
    } 

    function _generateNumsPool(address _nft, uint256 _min, uint256 _max) internal {
        for (uint256 i = _min; i <= _max; i++) {
            nft2numPool[_nft].add(i);
        }
    }

    function _getNumFromPool(address _nft, uint256 _seed) internal returns(uint256 num) { 
        if (nft2numPool[_nft].length() == 0) return num;
        uint256 index = Rand.randIndex(_seed, nft2numPool[_nft].length());
        num = nft2numPool[_nft].at(index);
        nft2numPool[_nft].remove(num);
    }
}
