// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import '../GameTicket2.sol';

contract MockGameTicket is GameTicket2 {
    function setStatus(address _user) external {
        status[_user] = true;
    }

    function setTicketBalance(address _user, uint _balance) external {
        tickets[_user] = _balance;
    }

    function increaseTicketBalance(address _user, uint amount) external {
        tickets[_user] = tickets[_user].add(amount);
    }
}