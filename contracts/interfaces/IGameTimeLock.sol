// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

interface IGameTimeLock {
    function lock(address _account, uint256 _amount) external;
}