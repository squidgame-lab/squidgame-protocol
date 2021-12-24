// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;
pragma experimental ABIEncoderV2;

import "./libraries/SafeMath128.sol";
import './libraries/TransferHelper.sol';
import './modules/ReentrancyGuard.sol';
import './modules/Pausable.sol';
import './modules/Configable.sol';
import './modules/WhiteList.sol';
import './modules/Initializable.sol';
import './interfaces/IERC20.sol';
import './interfaces/IRewardSource.sol';
import './interfaces/IShareToken.sol';

contract GameCollection is Configable, Pausable, WhiteList, ReentrancyGuard, Initializable {
    using SafeMath128 for uint128;
    address public buyToken;
    address[] public rewardSources;
  

    event NewRound(uint128 indexed value);
    event Claimed(address indexed user, uint128 indexed orderId, uint128 winAmount, uint128 shareAmount);
    event FeeRateChanged(uint indexed _old, uint indexed _new);

    receive() external payable {
    }
 
    function initialize(address _buyToken) external initializer {
        owner = msg.sender;
        buyToken = _buyToken;
    }

    function configure(address _buyToken) external onlyDev {
        buyToken = _buyToken;
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

    function setRewardSources(address[] calldata _rewardSources) external onlyDev {
        uint count = rewardSources.length;
        for(uint i; i<count; i++) {
            rewardSources.pop();
        }
        for(uint i; i<_rewardSources.length; i++) {
            rewardSources.push(_rewardSources[i]);
        }
    }

    function getRewardSources() external view returns (address[] memory) {
        return rewardSources;
    }

    function take() external view returns (uint) {
        uint rewardAmount;
        for(uint i; i<rewardSources.length; i++) {
            rewardAmount += IRewardSource(rewardSources[i]).getBalance();
        }
        return rewardAmount;
    }

    function withdraw() external onlyWhiteList {
        for(uint i; i<rewardSources.length; i++) {
            uint rewardAmount = IRewardSource(rewardSources[i]).getBalance();
            if(rewardAmount > 0) {
                IRewardSource(rewardSources[i]).withdraw(rewardAmount);
            }
        }

        uint balance = getBalance();
        if(balance == 0) return;

        if (buyToken == address(0)) {
            TransferHelper.safeTransferETH(msg.sender, balance);
        } else {
            TransferHelper.safeTransfer(buyToken, msg.sender, balance);
        }
    }

    function getBalance() public view returns (uint) {
        uint balance = address(this).balance;
        if(buyToken != address(0)) {
            balance = IERC20(buyToken).balanceOf(address(this));
        }
        return balance;
    }

}
