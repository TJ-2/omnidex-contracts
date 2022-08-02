// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "./OmniDexLoop.sol";
import "./interfaces/ICharmDojo.sol";
import "./interfaces/ITelosEscrow.sol";
import "./interfaces/IWTLOS.sol";
import "./interfaces/IXTLOS.sol";


contract checkTiers {

    ITelosEscrow TelosEscrow;
    ICharmDojo karmaContract;
    // ILoopingContract loopingContract;

    constructor(address _TelosEscrow, address _loopingContract, address _CharmDojo) public {
        TelosEscrow = ITelosEscrow(_TelosEscrow);
        karmaContract = ICharmDojo(_CharmDojo);
        // loopingContract = ILoopingContract(_loopingContract);
   }
        
    function getUserStakedCharmBalance(address _account) public view returns (uint256 charmAmount_) {
        return karmaContract.charmBalance(_account); 
    }

    function getTier(address _address) public view returns(string memory result){
        uint userBal = 100000;
        if(userBal<100000){
            result = "Bronze";
        }
        else if( userBal >= 100000 && userBal < 250000 ){
            result = "Silver";
        }
        else if(userBal >= 250000 && userBal < 500000 ){
            result = "Gold";
        }
        else{
            result = "Platinum";
        }
        return result;
    }

    function deposit(address _address) public view returns(string memory result){
        uint userBal = 100;
        if(userBal<100000){
            result = "Bronze";
        }
        else if( userBal >= 100000 && userBal < 250000 ){
            result = "Silver";
        }
        else if(userBal >= 250000 && userBal < 500000 ){
            result = "Gold";
        }
        else{
            result = "Platinum";
        }
        return result;
    }
}

contract depositTLOS {

    mapping(address => uint)public balances;

    IWTLOS wrapTLOS;
    IXTLOS xTLOS;

    constructor(address _wrapTLOS, address _xTLOS) public {
        wrapTLOS = IWTLOS(_wrapTLOS);
        xTLOS = IXTLOS(_xTLOS);
        }

    function Deposit()public payable{
        balances[msg.sender] += msg.value;
        wrapTLOS.deposit{value: msg.value }();
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }


    function withdrawMoney(uint _amount) public {
        address payable to = payable(msg.sender);
        to.transfer(getBalance());
    }

    function Withdraw(uint _amount) public {
        require (balances[msg.sender]>= _amount);
        wrapTLOS.withdraw(_amount);
        balances[msg.sender]-=_amount;
        payable(msg.sender).transfer(address(this).balance);
        // (bool sent,) = msg.sender.call{value: _amount}(“sent”);
        // require(sent, “Failed to Complete”);
    }
}


    /**
     * Get function to let the user know which tier they belong to
     * Deposit function to check which tier they belong to and enable them 
       to loop the appropriate times
     * Withdraw function to unwind their position. (As it is an Escrow contract, 
       they must first approve withdraw, (At which point the position is unwound,
       after escrow (5 days) they can withdraw their TLOS.

       Deposit function:
       - Check which tier they belon to 
       - Enable user to deposit according amount of TLOS
       - Send TLOS to staking contract
       - Receive sTLOS back (Store in contract)
            - Map users sTLOS balance to their account.
       - Mint xTLOS on 1:1 with sTLOS
       - Loop xTLOS according to tier they belong to

       Thoughts: 
       - Make sure there is no overflow or underflow on user tier
       - Make sure there is no re-entrancy on looping
       - Emergency withdraw function?
       - Wrong token deposit recovery?
       - Any only owner functions? 
       - Upgradability?

       Todo:
       - Match solidity compiler versions to looping contract
     */
    








