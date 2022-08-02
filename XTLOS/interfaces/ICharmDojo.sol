// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

interface ICharmDojo {
    function charmBalance(address _account) external view returns (uint256 charmAmount_);
}