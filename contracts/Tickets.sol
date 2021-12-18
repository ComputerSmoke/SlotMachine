//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ContextMixin.sol";
import "../interfaces/ITickets.sol";

//Tickets track slot machine ownership, as well as 
contract Tickets is ITickets,ERC1155,ContextMixin,Ownable {
    //OpenSea's ERC1155 Proxy Address - (0x207Fa8Df3a17D96Ca7EA4f2893fcdCb78a304101 for polygon)
    address openSeaProxy;
    //Each id can only be minted once to prevent changing machines after initial sell.
    mapping(uint256 => bool) exists;
    //Contracts authorised to make 
    mapping(address => bool) ticketFactories;
    mapping(address => bool) machineFactories;
    //Number of tickets and machines created (tracks first unused ID of each)
    uint256 ticketCount;
    uint256 machineCount;
    //Upper half of ids used to store machines, abstracted away from interface.
    uint256 machineOffset;
    //Take the address of OpenSea's ERC1155 Proxy, and the URI where metadata will be served by id.
    constructor(address _openSeaProxy, string memory _URI) ERC1155(_URI) Ownable() {
        openSeaProxy = _openSeaProxy;
        ticketCount = 0;
        machineCount = 0;
        //Store machines in upper half of ids
        machineOffset = 0xffffffffffffffffffffffffffffffff;
    }

    /**
   * Override isApprovedForAll to auto-approve OS's proxy contract
   */
    function isApprovedForAll(
        address _owner,
        address _operator
    ) public override view returns (bool isOperator) {
        // if OpenSea's ERC1155 Proxy Address is detected, auto-return true
       if (_operator == openSeaProxy) return true;
        // otherwise, use the default ERC1155.isApprovedForAll()
        return ERC1155.isApprovedForAll(_owner, _operator);
    }

    /**
     * This is used instead of msg.sender as transactions won't be sent by the original token owner, but by OpenSea.
     */
    function _msgSender()
        internal
        override
        view
        returns (address sender)
    {
        return ContextMixin.msgSender();
    }
    //Mint a new ticket. Can only be used once for each id.
    function mintTicket(uint256 _amount) external returns(uint256) {
        require(ticketFactories[msg.sender], "This address is not whitelisted to create new ticket types.");
        _mint(msg.sender, ticketCount, _amount, "");
        ticketCount++;
        return ticketCount;
    }
    //Mint a new machine. Can only be used once for each id.
    function mintMachine() external returns(uint256) {
        require(machineFactories[msg.sender], "This address is not whitelisted to create new machine ownership tokens.");
        _mint(msg.sender, machineCount+machineOffset, 1, "");
        machineCount++;
        return machineCount;
    }
    //Allow an address to create tickets. Will be useful for creating smart contracts that sell machines.
    function addTicketFactory(address _factory) external onlyOwner {
        ticketFactories[_factory] = true;
    }
    //Allow an address to create machine ownership tokens. Will be useful for creating smart contracts that sell machines.
    function addMachineFactory(address _factory) external onlyOwner {
        machineFactories[_factory] = true;
    }

    //Returns true if _user has the certificate of ownership for machine _id
    function ownsMachine(address _user, uint256 _id) external view returns(bool) {
        return balanceOf(_user, _id) > 0;
    }
}