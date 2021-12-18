// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISlotMachine {
    //Interactions
    /**
    Spin the slot machine
    */
    function spin(uint256 betAmount) external;
    
    //Views
    /**
    Get the minimum number of tickets to bet.
    */
    function getMinBetAmount() external view returns (uint256);
    /**
    Get the number of reels
    */
    function getReelCount() external view returns (uint8);
    /**
    Get the size of the reels
    */
    function getReelSize() external view returns (uint8);
    /**
    Get the encoding of the current reel states.
    */
    function getLine() external view returns (uint256);
    /**
    Get the state of the slot machine.
    0: stopped
    1: spinning
    */
    function getState() external view returns(uint8);
    /**
    Get the winning lines and their associated payout amounts.
    */
    function getLines() external view returns(uint256[] memory, uint256[] memory);

    //Math utilities
    /** 
    Encode an array of reel positions
    */
    function encodeState(uint8[] memory state) external pure returns (uint256);
    /**
    Decode an encoded set of reel positions to an array
     */
    function decodeState(uint256 encoding) external pure returns (uint8[] memory);
}