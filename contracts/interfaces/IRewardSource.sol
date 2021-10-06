// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

interface IRewardSource {
    function tickets(address _user) external view returns (uint);
    function buyToken() external view returns (address);
    function withdraw(uint _value) external returns (uint reward, uint fee);
    function getBalance() external view returns (uint);

    event Withdrawed(address indexed to, uint indexed reward, address feeTo, uint fee);
}
