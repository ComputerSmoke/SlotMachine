//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SlotMachine is ERC1155,Ownable,VRFConsumerBase {
    //Ticket to use for spin/rewards
    uint256 public constant TICKET = 0;
    //Characteristics of machine
    uint8 reelCount;
    uint8 reelSize;
    uint256 spinCost;
    //Current positions of reels
    uint256 line;
    //Maps encodings of paylines to their payout amount.
    mapping(uint256 => uint256) paylines;
    //State of machine
    enum SLOT_STATE {
        STOPPED,
        SPINNING
    }
    SLOT_STATE public state;
    //Emitted when we want a new VRF
    event RequestedRandomness(bytes32 requestId);
    //Emitted when spin completes
    event SpinCompletion(uint256 line);
    //Address that spun the machine
    address spinner;
    
    //Construct slot machine.
    constructor(
        address _vrfCoordinator,
        address _link,
        uint8 _reelCount,
        uint8 _reelSize,
        uint256 _spinCost,
        uint256 _initialSupply,
        uint256 _fee,
        uint256[] memory _paylines,
        uint256[] memory _paylineValues,
        bytes32 _keyhash,
        string _URI
    ) public VRFConsumerBase(_vrfCoordinator, _link) ERC1155(_URI) {
        require(reelCount <= 32, "Too many reels. Max: 32");
        require(_paylines.length == _paylineValues.length, "A different number of paylines and values were provided.");
        reelCount = _reelCount;
        reelSize = _reelSize;
        spinCost = _spinCost;

        for(uint i = 0; i < _paylines.length; i++) {
            paylines[_paylines[i]] = _paylineValues[i];
        }

        state = SLOT_STATE.STOPPED;
        fee = _fee;
        keyhash = _keyhash;
        _mint(address(this), TICKET, _initialSupply, "");
    }
    //Encode state from uint8 array.
    function encodeState(uint8[] memory state) public pure returns(uint256) {
        uint256 encoding = 0;
        for(uint i = 0; i < 32; i++) {
            encoding = encoding << 8;
            encoding = encoding | state[i];
        }
        return encoding;
    }
    //Decode state. Not useful internally because it returns a uint8 array.
    function decodeState(uint256 encoding) external pure returns(uint8[] memory) {
        uint8[] memory state = new uint[](reelCount);
        for(uint i = 0; i < reelCount; i++) {
            state[i] = uint8((encoding >> (248 - i*8)) & 0xFF);
        }
        return state;
    }
    
    //Spin function called by user
    function spin() external {
        require(state == SLOT_STATE.STOPPED, "Slot machine is currently spinning.");
        safeTransferFrom(msg.sender, address(this), TICKET, "");
        spinner = msg.sender;
        state = SLOT_STATE.SPINNING;
        bytes32 requestId = requestRandomness(keyhash, fee);
        emit RequestedRandomness(requestId);
    }
    //Called when randomness is filled - ie. slot machine stops spinning and pays out
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness)
        internal override {
        require(state == SLOT_STATE.SPINNING, "Slot machine is not spinning.");
        require(_randomness > 0, "random-not-found");
        line = _randomness;
        emit SpinCompletion(line);
        uint256 winnings = paylines[line];
        if(winnings == 0) return;
        
        safeTransferFrom(address(this), spinner, TICKET, winnings, "");
        // Reset
        state = SLOT_STATE.STOPPED;
    }
}