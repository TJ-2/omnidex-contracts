// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

interface ITelosEscrow {
    function deposit(address) payable external;
    function withdraw(uint) external;
}
