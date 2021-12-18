//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface ITickets {
    //Owner functions
    /**
    Add an address to the ticket factory whitelist, allowing them to mint new ticket types.
    */
    function addTicketFactory(address _factory) external;
    /**
    Allow an address to create machine ownership tokens. Will be useful for creating smart contracts that sell machines.
    */
    function addMachineFactory(address _factory) external;

    //Mint whitelist functions
    /**
    Mint a new ticket. Can only be used once for each id.
    */
    function mintTicket(uint256 _amount) external returns(uint256);
    /**
    Mint a new machine. Can only be used once for each id.
    */
    function mintMachine() external returns(uint256);

    //Views
    /**
    Returns true if user owns the certificate _id (ranging from 0 to 2^255).
    */
    function ownsMachine(address _user, uint256 _id) external view returns(bool);
}