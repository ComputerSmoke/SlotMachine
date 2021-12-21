//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ISlotMachine.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract SlotMachine is ISlotMachine,Ownable,VRFConsumerBase,ERC1155Holder {
    //Characteristics of machine
    uint8 public reelCount;
    uint8 public reelSize;
    uint256 public minBetAmount;
    //Ticket economics
    uint256 ticketId;
    IERC1155 tickets;
    //Track the amount owed to players. They can collect this, or use it to spin for rewards.
    mapping(address => uint256) debts;
    uint256 totalDebt;
    //Wheel spin payout economics
    ERC20 wheelToken;
    uint256[] wheelValues;
    uint256 maxWheelPayout;
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
        SPINNING,
        WHEEL
    }
    SLOT_STATE public state;
    //Emitted when we want a new VRF
    event RequestedRandomness(bytes32 requestId);
    //Emitted when spins complete
    event SpinCompletion(uint256 line);
    event WheelCompletion(uint256 wheelState);
    //Emittied when spins start
    event SpinStart(uint256 betAmount);
    event WheelStart(uint256 betAmount);
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
        uint256[] memory _wheelValues,//Spin wheel payout amounts
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
        //address of the ERC20 token used for wheel spin payouts.
        address _wheelTokenAddress,
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
        maxWheelPayout = 0;
        for(uint i = 0; i < _wheelValues.length; i++) {
            uint256 value = _wheelValues[i];
            wheelValues.push(value);
            if(maxWheelPayout < value) maxWheelPayout = value;
        }
        wheelToken = IERC20(wheelTokenAddress);

        state = SLOT_STATE.STOPPED;
        fee = _fee;
        keyhash = _keyhash;

        ticketId = uint256(_ticketId);
        machineId = uint256(_machineId) << 128;
        tickets = _ticketContract;
    }
    //Transfer tickets to recipient, minting new ones if necessary
    function payout(address _recipient, uint256 _amount) internal {
        require(_amount < mintBatchAmount, "Excessive transfer amount.");
        if(balanceOf(address(this)) < _amount) _mint(address(this), TICKET, mintBatchAmount-balanceOf(address(this)), "");
        safeTransferFrom(address(this), _recipient, TICKET, _amount, "");
    }
    
    //Spin function called by user
    function spinMachine(uint256 _betAmount) external {
        require(_betAmount >= minBetAmount, "Insufficient bet amount.");
        //Ensure machine is not committing to pay out more than it has.
        uint256 jackpotSize = tickets.balanceOf(address(this), ticketId);
        require(
            _betAmount * maxPayoutAmount <= jackpotSize-totalDebt, 
            "Bet amount is too large for current ticket jackpot."
        );
        require(
            _betAmount * maxPayoutAmount < wheelTokenholdings / maxWheelPayout,
            "Wheel does not have enough token backing to pay out potential win."
        );
        require(state == SLOT_STATE.STOPPED, "Slot machine is currently spinning.");
        tickets.safeTransferFrom(msg.sender, address(this), ticketId, _betAmount, "");
        betAmount = _betAmount;
        spinner = msg.sender;
        state = SLOT_STATE.SPINNING;
        bytes32 requestId = requestRandomness(keyhash, fee);
        emit RequestedRandomness(requestId);
        emit SpinStart(_betAmount);
    }
    //Spin the wheel with pending ticket rewards
    function spinWheel() external {
        require(debts[msg.sender] > 0, "You do not have any pending ticket rewards to spin with.");
        //Ensure machine is not committing to pay more than it has
        uint256 wheelTokenHoldings = wheelToken.balanceOf(address(this));
        //Interface should warn people if spinning the machine could give them more rewards than the machine can afford.
        require(
            debts[msg.sender] * maxWheelPayout <= wheelTokenHoldings, 
            "Machine does not have enough token rewards for you to spin the wheel at this time."
        );
        state = SLOT_STATE.WHEEL;
        bytes32 requestId = requestRandomness(keyhash, fee);
        emit RequestedRandomness(requestId);
        emit WheelStart(debts[msg.sender]);
    }
    //Called when randomness is filled - ie. slot machine or wheel stops spinning and pays out
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness)
        internal override {
        require(_randomness > 0, "random-not-found");
        if(state == SLOT_STATE.SPINNING) finishSpin(_randomness);
        else if(state == SLOT_STATE.WHEEL) finishWheel(_randomness);
        state = SLOT_STATE.STOPPED;
    }
    //Slot machine stops spinning and pays out
    function finishSpin(uint256 _randomness) internal {
        line = modLine(_randomness);

        uint256 winnings = paylines[line]*betAmount;
        if(winnings == 0) return;
        
        creditTab(spinner, winnings);
        emit SpinCompletion(line);
    }
    //Add ticket credits to a user's tab. This can be withdrawn with withdrawTickets, or used to spin the wheel.
    function creditTab(address _user, uint256 amount) internal {
        debts[_user] += amount;
        totalDebt += amount;
    }
    //Wheel stops spinning and pays out
    function finishWheel(uint256 _randomness) internal {
        uint256 wheelState = _randomness % wheelValues.length;
        uint256 payoutAmount = wheelValues[wheelState]*debts[spinner];
        totalDebt -= debts[spinner];
        debts[spinner] = 0;
        if(payoutAmount == 0) return;
        wheelToken.safeTransfer(spinner, payoutAmount);
        emit WheelCompletion(payoutAmount);
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
    function getPaylines() external view returns(uint256[] memory) {
        return paylineArray;
    }
    function getPaylineValue(uint256 _payline) external view returns(uint256) {
        return paylines[_payline];
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