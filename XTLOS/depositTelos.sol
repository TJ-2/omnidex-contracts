// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "./interfaces/IOmniDexLoop.sol";
import "./interfaces/ICharmDojo.sol";
import "./interfaces/ITelosEscrow.sol";
import "./interfaces/IWTLOS.sol";
import "./interfaces/IXTLOS.sol";

contract depositTLOS {

    mapping(address => uint) public balances;
    mapping(address => uint) public XTLOSBalances;

    IWTLOS wrapTLOS;
    IXTLOS xTLOS;
    IOmniDexLoop omnidexLoop;
    ICharmDojo karmaContract;

    constructor(address _wrapTLOS, address _xTLOS, address _loopingContract, address _CharmDojo) {
        wrapTLOS = IWTLOS(_wrapTLOS);
        xTLOS = IXTLOS(_xTLOS);
        omnidexLoop = IOmniDexLoop(_loopingContract);
        karmaContract = ICharmDojo(_CharmDojo);
        }

    function getTier(address _address) public view returns(string memory result, uint id){
        uint256 userBal = karmaContract.charmBalance(_address);
        // uint256 userBal = 100000;
        if(userBal<100000){
            return ("Bronze",1);
        }
        else if( userBal >= 100000 && userBal < 250000 ){
            return ("Silver",2);
        }
        else if(userBal >= 250000 && userBal < 500000 ){
            return ("Gold",3);
        }
        else{
            return ("Platinum",4);
        }
    }

    function Deposit(address _address) public payable{
        
        balances[msg.sender] += msg.value;
        wrapTLOS.deposit{value: msg.value }();
        xTLOS.mint(address(this), msg.value);
        XTLOSBalances[msg.sender] += msg.value;

        uint256 maxDeposit =1000;
        uint256 principal = msg.value;
        require(principal<maxDeposit, "Exceeded maximum deposit allowance");
        uint id; (,id) = getTier(_address);
        
        if(id==1){
            uint256 iterations = 2;
            omnidexLoop.enterPosition(principal, iterations, _address);
            }
        else if(id==2) {
            uint256 iterations = 3;
            omnidexLoop.enterPosition(principal, iterations, _address);
        }
        else if(id==3) {
            uint256 iterations = 8;
            omnidexLoop.enterPosition(principal, iterations, _address);
        }
        else if(id==4) {
            uint256 iterations = 20;
            omnidexLoop.enterPosition(principal, iterations, _address);
        }
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function Withdraw(uint _amount) public {
        require (balances[msg.sender]>= _amount);
        wrapTLOS.withdraw(_amount);
        balances[msg.sender]-=_amount;
        payable(msg.sender).transfer(address(this).balance);
        // (bool sent,) = msg.sender.call{value: _amount}(“sent”);
        // require(sent, “Failed to Complete”);
    }

    // function withdrawMoney(uint _amount) public {
    //    address payable to = payable(msg.sender);
    //    to.transfer(getBalance());
    // }

    // unwrap borrowed wTLOS, 
    // Deposit to sTLOS staking contract
    // Mint equivilent xTLOS 
    // deposit xTLOS back to the LoopContract "Enter position" (Make sure it doesn't loop infinite times)
    function wTLOStoXTLOSConversion(uint256 amount, address _address) public {
        wrapTLOS.withdraw(amount);
        wrapTLOS.deposit{value: amount }();  // Dummy: Replace with staking contract
        xTLOS.mint(address(this), amount);
        XTLOSBalances[_address] += amount;
        xTLOS.transfer(msg.sender, amount);
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
    









