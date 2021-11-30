// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

interface IGamePoolShareRule {
        
    function getShareAmount(address _pool) external view returns (uint128 participationAmount, uint128 topAmount);
}
