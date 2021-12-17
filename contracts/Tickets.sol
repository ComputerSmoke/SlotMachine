//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ContextMixin.sol";

//Tickets track slot machine ownership, as well as 
contract Tickets is ERC1155,ContextMixin,Ownable {
    //OpenSea's ERC1155 Proxy Address - (0x207Fa8Df3a17D96Ca7EA4f2893fcdCb78a304101 for polygon)
    address openSeaProxy;
    //Each id can only be minted once to prevent changing machines after initial sell.
    mapping(uint256 => bool) exists;
    //Take the address of OpenSea's ERC1155 Proxy, and the URI where metadata will be served by id.
    constructor(address _openSeaProxy, string memory _URI) ERC1155(_URI) {
        openSeaProxy = _openSeaProxy;
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
    function mintTicket(uint256 _id, uint256 _amount) external onlyOwner {
        //If ID is in the upper 128 bits, it is too high since we use the upper half for machine ids.
        require((~_id) & 0xffffffffffffffffffffffffffffffff == 0, "Id is too high.");
        require(!exists[_id], "This id has already been used.");
        _mint(msg.sender, _id, _amount, "");
    }
    //Mint a new machine. Can only be used once for each id.
    function mintMachine(uint256 _id) external onlyOwner {
        //If ID is in the upper 128 bits, it is too high since we use the upper half for machine ids.
        require((~_id) & 0xffffffffffffffffffffffffffffffff == 0, "Id is too high.");
        require(!exists[_id], "This id has already been used.");
        _mint(msg.sender, _id << 128, 1, "");
    }
}