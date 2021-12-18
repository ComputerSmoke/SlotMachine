//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ISlotMachine.sol";

contract SlotMachine is ISlotMachine,Ownable,VRFConsumerBase {
    //Characteristics of machine
    uint8 reelCount;
    uint8 reelSize;
    uint256 minBetAmount;
    //Ticket economics
    uint256 ticketId;
    IERC1155 tickets;
    //ID of machine in tickets contract to verify ownership of machine
    uint256 machineId;
    uint256 maxPayoutAmount;
    //Current positions of reels
    uint256 line;
    //Maps encodings of paylines to their payout amount.
    mapping(uint256 => uint256) paylines;
    uint256[] paylineArray;
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
    //Emitted when tokens are purchased from the machine
    event TicketsPurchased(uint256 amountPurchased);
    //Address that spun the machine
    address spinner;
    //Amount bet on spin
    uint256 betAmount;
    
    //Construct slot machine.
    constructor(
        //Machine characteristics
        uint8 _reelCount, //Number of reels
        uint8 _reelSize, //Size of each reel
        uint256[] memory _paylines, //Sequences that pay out (uint256 encoding)
        uint256[] memory _paylineValues,//Corresponding amount to pay out for each sequence at corresponding index
        //Economics
        uint256 _minBetAmount, //Minimum cost to play
        //necessary for getting VRFs from Chainlink
        address _vrfCoordinator,
        address _link,
        uint256 _fee,
        bytes32 _keyhash,
        //ID of the ticket in ERC1155 ticket contract
        uint128 _ticketId,
        address _ticketContract,
        //ID of the machine in the ERC1155 ticket contract (For verifying ownership)
        uint128 _machineId
    ) public VRFConsumerBase(_vrfCoordinator, _link) {
        require(reelCount <= 32, "Too many reels. Max: 32");
        require(_paylines.length == _paylineValues.length, "A different number of paylines and values were provided.");

        reelCount = _reelCount;
        reelSize = _reelSize;
        minBetAmount = _minBetAmount;
        for(uint i = 0; i < _paylines.length; i++) {
            paylines[_paylines[i]] = _paylineValues[i];
            paylineArray[i] = _paylines[i];
            if(_paylineValues[i] > maxPayoutAmount) maxPayoutAmount = _paylineValues[i];
        }

        state = SLOT_STATE.STOPPED;
        fee = _fee;
        keyhash = _keyhash;

        ticketId = uint256(_ticketId);
        machineId = uint256(_machineId) << 128;
        tickets = _ticketContract;
    }
    //Used to purchase tickets from machine
    function buyTickets(uint256 _amount) external {
        uint256 cost = _amount * ticketCost;
        backingToken.safeTransferFrom(msg.sender, address(this), cost);
        payout(msg.sender, _amount);
    }
    //Transfer tickets to recipient, minting new ones if necessary
    function payout(address _recipient, uint256 _amount) internal {
        require(_amount < mintBatchAmount, "Excessive transfer amount.");
        if(balanceOf(address(this)) < _amount) _mint(address(this), TICKET, mintBatchAmount-balanceOf(address(this)), "");
        safeTransferFrom(address(this), _recipient, TICKET, _amount, "");
    }
    
    //Spin function called by user
    function spin(uint256 _betAmount) external {
        require(_betAmount >= minBetAmount, "Insufficient bet amount.");
        require(
            _betAmount < uint256(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) / maxPayoutAmount, 
            "Bet amount is too large."
        );
        require(state == SLOT_STATE.STOPPED, "Slot machine is currently spinning.");
        safeTransferFrom(msg.sender, address(this), TICKET, _betAmount, "");
        betAmount = _betAmount;
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
        line = modLine(_randomness);

        emit SpinCompletion(line);
        uint256 winnings = paylines[line]*betAmount;
        if(winnings == 0) return;
        
        payout(spinner, winnings);
        state = SLOT_STATE.STOPPED;
    }
    //Convert random uint256 to an encoding of reel states not exceeding reelSize
    function modLine(uint256 _randomness) internal pure returns (uint256) {
        uint256 result = 0;
        for(uint i = 0; i < reelCount; i++) {
            uint256 reelValue = uint256(((_randomness >> (248 - i*8)) & 0xFF) % reelSize);
            result = result | uint256(reelValue << (248-i*8));
        }
        return result;
    }

    //Variable views:
    function getMinBetAmount() external view returns(uint256) {
        return minBetAmount;
    }
    function getReelCount() external view returns (uint8) {
        return reelCount;
    }
    function getReelSize() external view returns (uint8) {
        return reelSize;
    }
    function getLine() external view returns (uint256) {
        return line;
    }
    function getState() external view returns(uint8) {
        return state;
    }
    function getLines() external view returns(uint256[] memory, uint256[] memory) {
        uint256[] memory payoutArray = new uint256(paylineArray.length);
        for(uint i = 0; i < paylineArray.length; i++) {
            payoutArray[i] = paylines[paylineArray[i]];
        }
        return (paylineArray, payoutArray);
    }
    function getTicketId() external view returns(uint128) {
        return uint128(ticketId);
    }
    function getTicketContract() external view returns(address) {
        return address(tickets);
    }
    function getMachineId() external view returns(uint128) {
        return uint128(machineId >> 128);
    }

    //Math utils for other contracts
    //Encode state from uint8 array.
    function encodeState(uint8[] memory state) external pure returns(uint256) {
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
}