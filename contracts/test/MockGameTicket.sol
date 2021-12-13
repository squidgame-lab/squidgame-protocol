// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import '../GameTicket2.sol';

contract MockGameTicket is GameTicket2 {
    function setStatus(address _user) external {
        status[_user] = true;
    }
}