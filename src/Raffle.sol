// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample raffle contract
 * @author Andrea De Blasio
 * @notice This contract is a sample raffle contract
 * @dev Implements Chainlink VRFv2
 * @custom:experimental Tips for developers: Custom Error is more gas efficient than require.
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TranferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);
    //         --- Type Declaration ---

    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1

    }

    //         --- State Variables ---
    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; // Duration of the lottery in seconds
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimestamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    //         --- Events ---
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
        s_lastTimestamp = block.timestamp;
    }

    function enterRaffle() external payable {
        //require(msg.value >= i_entranceFee, "Not enough ETH sent");
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Automation nodes call to see if it's time to perform an upkeep.
     * The following should be true:
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is in the OPEN state
     * 3. The contract has ETH (aka, players)
     * 4. (Implicit) The subscription is funded with LINK
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        // check to see if enough time has passed
        // 1. The time interval has passed between raffle runs
        bool timeHasPassed = (block.timestamp - s_lastTimestamp) >= i_interval;
        // 2. The raffle is in the OPEN state
        bool isOpen = RaffleState.OPEN == s_raffleState;
        // 3. The contract has ETH (aka, players)
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        // return the upkeepNeeded boolean
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        s_raffleState = RaffleState.CALCULATING;
        // Chainlink VRFv2 need 2 transactions
        // 1. Request the RNG
        // 2. Get the RNG
        i_vrfCoordinator.requestRandomWords(
            i_gasLane, i_subscriptionId, REQUEST_CONFIRMATION, i_callbackGasLimit, NUM_WORDS
        );
    }

    function pickWinner() external {}
    // CEI: Checks, Effects, Interactions pattern
    // Checks: if, require, revert -> Is more gas efficient
    // Effects: state changes
    // Interactions: external calls

    function fulfillRandomWords(uint256, /* requestId */ uint256[] memory randomWords) internal override {
        // • Checks
        // • Effects (ours own contract)
        uint256 indexOfWinnner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinnner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;

        // Clear the players array, and update the lastTimestamp
        s_players = new address payable[](0);
        s_lastTimestamp = block.timestamp;

        // • Interactions
        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TranferFailed();
        }

        emit PickedWinner(winner);
    }

    //         --- Getters ---
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }
}
