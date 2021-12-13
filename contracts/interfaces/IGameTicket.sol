// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

interface IGameTicket {
    function buyToken() external view returns (address);
    function unit() external view returns (uint);
    function gameToken() external view returns (address);
    function gameTokenUnit() external view returns (uint);
    function tickets(address) external view returns (uint);
    function status(address) external view returns (bool);

    function buy(uint _value, address _to) external returns (bool);
}