// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;
pragma experimental ABIEncoderV2;

import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";
import "./modules/ReentrancyGuard.sol";
import "./modules/Configable.sol";
import "./modules/Initializable.sol";
import "./interfaces/IERC20.sol";

interface IGameNFT {
    function mint(address to) external returns(uint256);
}

contract GameNFTMarket is Configable, ReentrancyGuard, Initializable {
    using SafeMath for uint256;

    struct SellConf {
        address nft;
        address paymentToken;
        uint price;
        uint startTime;
        uint endTime;
        uint total;
        uint balance;
    }

    SellConf[] sellConfs;
    mapping(address => uint) nft2conf;

    event SetSellConf(address user, address nft, address paymenToken, uint256 price, uint256 startTime, uint256 endTime, uint256 _total);
    event Buy(address user, address miner, uint256 amount, uint256 price);

    function initialize() external initializer {
        owner = msg.sender;
        sellConfs.push(SellConf({nft: address(0), paymentToken: address(0), price: 0, startTime: 0, endTime: 0, total: 0, balance: 0}));
    }

    function getSellConf(address _nft) public view returns(SellConf memory conf) {
        if(nft2conf[_nft] == 0) return conf;
        conf = sellConfs[nft2conf[_nft]];
    }

    function getSellConfList(address[] calldata _nfts) external view returns(SellConf[] memory confList) {
        confList = new SellConf[](_nfts.length);
        for (uint i = 0; i < _nfts.length; i++) {
            confList[i] = getSellConf(_nfts[i]);
        }
    }

    function setSellConf(address _nft, address _paymentToken, uint256 _price, uint _startTime, uint _endTime, uint _total) public onlyDev {
        require(_nft != address(0), 'GNM: INVALID_NFT_ADDR');
        if (nft2conf[_nft] != 0) {
            SellConf storage conf = sellConfs[nft2conf[_nft]];
            conf.paymentToken = _paymentToken;
            conf.price = _price;
            conf.startTime = _startTime;
            conf.endTime = _endTime;
            if (_total >= conf.total) {
                conf.balance = conf.balance.add(_total.sub(conf.total));
                conf.total = _total;
            } else {
                require(conf.balance >= conf.total.sub(_total), 'GNM: INVALID_TOTAL');
                conf.balance = conf.balance.sub(conf.total.sub(_total));
                conf.total = _total;
            }
        } else {
            uint pid = sellConfs.length;
            sellConfs.push(SellConf({
                nft: _nft,
                paymentToken: _paymentToken,
                price: _price,
                startTime: _startTime,
                endTime: _endTime,
                total: _total,
                balance: _total            
            }));
            nft2conf[_nft] = pid;
        }
        emit SetSellConf(msg.sender, _nft, _paymentToken, _price, _startTime, _endTime, _total);
    }

    function batchSetMinerConf(
        address[] calldata _nfts,
        address[] calldata _paymentTokens,
        uint256[] calldata _prices,
        uint256[] calldata _startTimes,
        uint256[] calldata _endTimes,
        uint256[] calldata _totals
    ) external onlyDev {
        require(_nfts.length == _paymentTokens.length && _paymentTokens.length == _prices.length, 'GNM: INVALID_ARG_LENGTH');
        for (uint256 i = 0; i < _nfts.length; i++) {
            setSellConf(_nfts[i], _paymentTokens[i], _prices[i], _startTimes[i], _endTimes[i], _totals[i]);
        }
    }

    // function buy(address _nft, uint256 _amount) external returns(uint256){
    //     require(nft2conf[_nft] != 0, 'GNM: INVALID_NFT_ADDR');
    //     MinerConf memory conf = sellConfs[nft2conf[_nft]];
    //     require(!conf.isPaused, 'GMM: SELL_PAUSED');
    //     uint256 value = _amount.mul(conf.price);
    //     TransferHelper.safeTransferFrom(conf.paymentToken, msg.sender, team(), value);
    //     IGameMiner(conf.miner).mint(msg.sender, uint32(minerId), _amount);
    //     emit BuyMiner(msg.sender, conf.miner, _amount, conf.price);
    // }
}