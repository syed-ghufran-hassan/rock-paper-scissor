// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/rockpaperscissor.sol";

contract RockPaperScissorsTest is Test {
    // Events for testing
    event GameCreated(uint256 indexed gameId, address indexed creator, uint256 bet, uint256 totalTurns);
    event PlayerJoined(uint256 indexed gameId, address indexed player);
    event MoveCommitted(uint256 indexed gameId, address indexed player, uint256 currentTurn);
    event MoveRevealed(
        uint256 indexed gameId, address indexed player, RockPaperScissors.Move move, uint256 currentTurn
    );
    event TurnCompleted(uint256 indexed gameId, address winner, uint256 currentTurn);
    event GameFinished(uint256 indexed gameId, address winner, uint256 prize);
    event GameCancelled(uint256 indexed gameId);
    event JoinTimeoutUpdated(uint256 oldTimeout, uint256 newTimeout);
    event FeeCollected(uint256 gameId, uint256 feeAmount);
    event FeeWithdrawn(address indexed admin, uint256 amount);

    // Contract
    RockPaperScissors public game;

    // Test accounts
    address public admin;
    address public playerA;
    address public playerB;
    address public playerC;

    // Test constants
    uint256 constant BET_AMOUNT = 0.1 ether;
    uint256 constant MIN_BET = 0.01 ether;
    uint256 constant TIMEOUT = 10 minutes;
    uint256 constant TOTAL_TURNS = 3; // Must be odd
    uint256 constant PROTOCOL_FEE_PERCENT = 10;

    // Game ID for tests
    uint256 public gameId;

    // Setup before each test
    function setUp() public {
        // Set up addresses
        admin = address(this);
        playerA = makeAddr("playerA");
        playerB = makeAddr("playerB");
        playerC = makeAddr("playerC");

        // Fund the players
        vm.deal(playerA, 10 ether);
        vm.deal(playerB, 10 ether);
        vm.deal(playerC, 10 ether);

        // Deploy contract
        game = new RockPaperScissors();
    }

    // ==================== GAME CREATION TESTS ====================

    function testCreateGame() public {
        vm.startPrank(playerA);

        // Create a game with ETH
        vm.expectEmit(true, true, false, true);
        emit GameCreated(0, playerA, BET_AMOUNT, TOTAL_TURNS);

        gameId = game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);
        vm.stopPrank();

        // Verify game details using the public getter
        RockPaperScissors.Game memory g = game.games(gameId);

        assertEq(g.playerA, playerA);
        assertEq(g.playerB, address(0));
        assertEq(g.bet, BET_AMOUNT);
        assertEq(g.timeoutInterval, TIMEOUT);
        assertEq(g.totalTurns, TOTAL_TURNS);
        assertEq(g.currentTurn, 1);
        assertEq(g.scoreA, 0);
        assertEq(g.scoreB, 0);
        assertEq(uint256(g.state), uint256(RockPaperScissors.GameState.Created));
        assertEq(g.joinDeadline, g.creationTime + game.joinTimeout());
    }

    function test_RevertWhen_CreateGameWithEvenTurns() public {
        vm.startPrank(playerA);
        // Should fail because turns must be odd
        vm.expectRevert("Total turns must be odd");
        game.createGame{value: BET_AMOUNT}(2, TIMEOUT);
        vm.stopPrank();
    }

    function test_RevertWhen_CreateGameWithZeroTurns() public {
        vm.startPrank(playerA);
        vm.expectRevert("Must have at least one turn");
        game.createGame{value: BET_AMOUNT}(0, TIMEOUT);
        vm.stopPrank();
    }

    function test_RevertWhen_CreateGameWithSmallBet() public {
        vm.startPrank(playerA);
        vm.expectRevert("Bet amount too small");
        game.createGame{value: MIN_BET - 1}(TOTAL_TURNS, TIMEOUT);
        vm.stopPrank();
    }

    function test_RevertWhen_CreateGameWithShortTimeout() public {
        vm.startPrank(playerA);
        vm.expectRevert("Timeout must be at least 5 minutes");
        game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, 4 minutes);
        vm.stopPrank();
    }

    // ==================== GAME JOINING TESTS ====================

    function testJoinGame() public {
        // First create a game
        vm.prank(playerA);
        gameId = game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Now join the game
        vm.startPrank(playerB);
        vm.expectEmit(true, true, false, true);
        emit PlayerJoined(gameId, playerB);

        game.joinGame{value: BET_AMOUNT}(gameId);
        vm.stopPrank();

        // Verify game state
        RockPaperScissors.Game memory g = game.games(gameId);

        assertEq(g.playerA, playerA);
        assertEq(g.playerB, playerB);
        assertEq(uint256(g.state), uint256(RockPaperScissors.GameState.Created));
    }

    function test_RevertWhen_JoinGameWithWrongBet() public {
        // First create a game
        vm.prank(playerA);
        gameId = game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Try to join with wrong bet amount
        vm.prank(playerB);
        vm.expectRevert("Bet amount must match creator's bet");
        game.joinGame{value: BET_AMOUNT + 0.1 ether}(gameId);
    }

    function test_RevertWhen_JoinOwnGame() public {
        // First create a game
        vm.prank(playerA);
        gameId = game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Try to join own game
        vm.prank(playerA);
        vm.expectRevert("Cannot join your own game");
        game.joinGame{value: BET_AMOUNT}(gameId);
    }

    function test_RevertWhen_JoinNonExistentGame() public {
        vm.prank(playerB);
        vm.expectRevert();
        game.joinGame{value: BET_AMOUNT}(999);
    }

    function test_RevertWhen_JoinAfterDeadline() public {
        // Create a game
        vm.prank(playerA);
        gameId = game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Fast forward past join deadline
        vm.warp(block.timestamp + game.joinTimeout() + 1);

        // Try to join
        vm.prank(playerB);
        vm.expectRevert("Join deadline passed");
        game.joinGame{value: BET_AMOUNT}(gameId);
    }

    // ==================== GAMEPLAY TESTS ====================

    // Helper function to create and join a game
    function createAndJoinGame() internal returns (uint256) {
        vm.prank(playerA);
        uint256 id = game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        vm.prank(playerB);
        game.joinGame{value: BET_AMOUNT}(id);

        return id;
    }

    function testCommitMoves() public {
        gameId = createAndJoinGame();

        // Player A commits
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        vm.expectEmit(true, true, false, true);
        emit MoveCommitted(gameId, playerA, 1);
        game.commitMove(gameId, commitA);

        // Player B commits
        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        vm.expectEmit(true, true, false, true);
        emit MoveCommitted(gameId, playerB, 1);
        game.commitMove(gameId, commitB);

        // Verify game state
        RockPaperScissors.Game memory g = game.games(gameId);

        assertEq(g.commitA, commitA);
        assertEq(g.commitB, commitB);
        assertEq(uint256(g.state), uint256(RockPaperScissors.GameState.Committed));
    }

    function test_RevertWhen_CommitBeforeGameJoined() public {
        // Create game but don't join
        vm.prank(playerA);
        gameId = game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Try to commit before game is joined
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        vm.expectRevert("Waiting for player B to join");
        game.commitMove(gameId, commitA);
    }

    function test_RevertWhen_CommitTwice() public {
        gameId = createAndJoinGame();

        // Player A commits once
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        // Try to commit again
        vm.prank(playerA);
        vm.expectRevert("Already committed");
        game.commitMove(gameId, commitA);
    }

    function testRevealMoves() public {
        gameId = createAndJoinGame();

        // Commit moves
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // Reveal moves
        vm.prank(playerA);
        vm.expectEmit(true, true, false, true);
        emit MoveRevealed(gameId, playerA, RockPaperScissors.Move.Rock, 1);
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Rock), saltA);

        vm.prank(playerB);
        vm.expectEmit(true, true, false, true);
        emit MoveRevealed(gameId, playerB, RockPaperScissors.Move.Paper, 1);
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Paper), saltB);

        // Verify game state - after both reveals, should be ready for next turn
        RockPaperScissors.Game memory g = game.games(gameId);

        // Paper beats rock, so Player B should have 1 point
        assertEq(uint256(g.moveA), uint256(RockPaperScissors.Move.None)); // Moves reset for next turn
        assertEq(uint256(g.moveB), uint256(RockPaperScissors.Move.None));
        assertEq(g.scoreA, 0);
        assertEq(g.scoreB, 1);
        assertEq(g.currentTurn, 2); // Advanced to turn 2
        assertEq(uint256(g.state), uint256(RockPaperScissors.GameState.Committed));
    }

    // Helper function to play a single turn
    function playTurn(uint256 _gameId, RockPaperScissors.Move moveA, RockPaperScissors.Move moveB) internal {
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A", _gameId, uint8(moveA)));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(moveA), saltA));

        vm.prank(playerA);
        game.commitMove(_gameId, commitA);

        bytes32 saltB = keccak256(abi.encodePacked("salt for player B", _gameId, uint8(moveB)));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(moveB), saltB));

        vm.prank(playerB);
        game.commitMove(_gameId, commitB);

        vm.prank(playerA);
        game.revealMove(_gameId, uint8(moveA), saltA);

        vm.prank(playerB);
        game.revealMove(_gameId, uint8(moveB), saltB);
    }

    function testCompleteGamePlayerBWins() public {
        gameId = createAndJoinGame();

        // First turn: A=Rock, B=Paper (B wins)
        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Paper);

        // Second turn: A=Scissors, B=Rock (B wins)
        playTurn(gameId, RockPaperScissors.Move.Scissors, RockPaperScissors.Move.Rock);

        // Third turn: A=Paper, B=Scissors (B wins)
        // This should end the game
        uint256 playerBBalanceBefore = playerB.balance;

        vm.expectEmit(true, true, false, true);
        emit GameFinished(gameId, playerB, (BET_AMOUNT * 2 * (100 - PROTOCOL_FEE_PERCENT)) / 100);

        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Scissors);

        // Verify game state
        RockPaperScissors.Game memory g = game.games(gameId);

        assertEq(uint256(g.state), uint256(RockPaperScissors.GameState.Finished));

        // Verify player B received prize
        uint256 expectedPrize = (BET_AMOUNT * 2) * (100 - PROTOCOL_FEE_PERCENT) / 100;
        assertEq(playerB.balance - playerBBalanceBefore, expectedPrize);
    }

    function testCompleteGamePlayerAWins() public {
        gameId = createAndJoinGame();

        // First turn: A=Paper, B=Rock (A wins)
        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Rock);

        // Second turn: A=Rock, B=Scissors (A wins)
        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Scissors);

        // Check state before final turn
        RockPaperScissors.Game memory g = game.games(gameId);
        assertEq(g.scoreA, 2);
        assertEq(g.scoreB, 0);

        // Third turn (doesn't matter who wins, A already has majority)
        uint256 playerABalanceBefore = playerA.balance;

        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Rock);

        // Verify player A received prize
        uint256 expectedPrize = (BET_AMOUNT * 2) * (100 - PROTOCOL_FEE_PERCENT) / 100;
        assertEq(playerA.balance - playerABalanceBefore, expectedPrize);
    }

    function testTieGame() public {
        // Create 1-turn game for tie scenario
        vm.prank(playerA);
        gameId = game.createGame{value: BET_AMOUNT}(1, TIMEOUT);

        vm.prank(playerB);
        game.joinGame{value: BET_AMOUNT}(gameId);

        // Both players play Rock (creates a tie)
        uint256 playerABalanceBefore = playerA.balance;
        uint256 playerBBalanceBefore = playerB.balance;

        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Rock);

        // Verify game state
        RockPaperScissors.Game memory g = game.games(gameId);

        assertEq(g.scoreA, 0);
        assertEq(g.scoreB, 0);
        assertEq(uint256(g.state), uint256(RockPaperScissors.GameState.Finished));

        // Verify both players received half of pot minus fees
        uint256 totalPot = BET_AMOUNT * 2;
        uint256 fee = (totalPot * PROTOCOL_FEE_PERCENT) / 100;
        uint256 refundPerPlayer = (totalPot - fee) / 2;

        assertEq(playerA.balance - playerABalanceBefore, refundPerPlayer);
        assertEq(playerB.balance - playerBBalanceBefore, refundPerPlayer);
    }

    // ==================== TIMEOUT TESTS ====================

    function testTimeoutJoin() public {
        // Create a game
        vm.prank(playerA);
        gameId = game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Fast forward past join deadline
        vm.warp(block.timestamp + game.joinTimeout() + 1);

        // Check if can timeout
        bool canTimeout = game.canTimeoutJoin(gameId);
        assertTrue(canTimeout);

        // Execute timeout
        vm.prank(playerC); // Any address can trigger timeout
        vm.expectEmit(true, false, false, true);
        emit GameCancelled(gameId);
        game.timeoutJoin(gameId);

        // Verify game state
        RockPaperScissors.Game memory g = game.games(gameId);

        assertEq(uint256(g.state), uint256(RockPaperScissors.GameState.Cancelled));

        // Verify refund
        uint256 playerABalance = playerA.balance;
        assertTrue(playerABalance > 9.9 ether); // Got back bet
    }

    function testTimeoutRevealOnePlayerRevealed() public {
        gameId = createAndJoinGame();

        // Player A commits
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        // Player B commits
        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // Only player A reveals
        vm.prank(playerA);
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Rock), saltA);

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + TIMEOUT + 1);

        // Check if can timeout
        (bool canTimeout, address winnerIfTimeout) = game.canTimeoutReveal(gameId);
        assertTrue(canTimeout);
        assertEq(winnerIfTimeout, playerA);

        // Execute timeout - player A should win
        uint256 playerABalanceBefore = playerA.balance;

        vm.prank(playerA);
        vm.expectEmit(true, true, false, true);
        emit GameFinished(gameId, playerA, (BET_AMOUNT * 2 * (100 - PROTOCOL_FEE_PERCENT)) / 100);
        game.timeoutReveal(gameId);

        // Verify game state
        RockPaperScissors.Game memory g = game.games(gameId);

        assertEq(uint256(g.state), uint256(RockPaperScissors.GameState.Finished));

        // Verify player A received prize
        uint256 expectedPrize = (BET_AMOUNT * 2) * (100 - PROTOCOL_FEE_PERCENT) / 100;
        assertEq(playerA.balance - playerABalanceBefore, expectedPrize);
    }

    function testTimeoutRevealNoReveals() public {
        gameId = createAndJoinGame();

        // Both players commit
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // No one reveals

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + TIMEOUT + 1);

        // Check if can timeout
        (bool canTimeout, address winnerIfTimeout) = game.canTimeoutReveal(gameId);
        assertTrue(canTimeout);
        assertEq(winnerIfTimeout, address(0)); // No winner

        // Execute timeout - game should be cancelled
        uint256 playerABalanceBefore = playerA.balance;
        uint256 playerBBalanceBefore = playerB.balance;

        vm.prank(playerA);
        vm.expectEmit(true, false, false, true);
        emit GameCancelled(gameId);
        game.timeoutReveal(gameId);

        // Verify game state
        RockPaperScissors.Game memory g = game.games(gameId);

        assertEq(uint256(g.state), uint256(RockPaperScissors.GameState.Cancelled));

        // Verify both players received refunds
        assertEq(playerA.balance - playerABalanceBefore, BET_AMOUNT);
        assertEq(playerB.balance - playerBBalanceBefore, BET_AMOUNT);
    }

    // ==================== ADMIN TESTS ====================

    function testSetJoinTimeout() public {
        uint256 oldTimeout = game.joinTimeout();
        uint256 newTimeout = 48 hours;

        vm.expectEmit(true, false, false, true);
        emit JoinTimeoutUpdated(oldTimeout, newTimeout);

        game.setJoinTimeout(newTimeout);

        assertEq(game.joinTimeout(), newTimeout);
    }

    function test_RevertWhen_SetJoinTimeoutNonAdmin() public {
        uint256 newTimeout = 48 hours;

        vm.prank(playerA);
        vm.expectRevert("Only owner can set timeout");
        game.setJoinTimeout(newTimeout);
    }

    function test_RevertWhen_SetJoinTimeoutTooShort() public {
        vm.expectRevert("Timeout must be at least 1 hour");
        game.setJoinTimeout(3599); // 59 minutes 59 seconds
    }

    function testSetAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        game.setAdmin(newAdmin);

        assertEq(game.adminAddress(), newAdmin);
        assertEq(game.owner(), newAdmin);
    }

    function test_RevertWhen_SetAdminNonAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(playerA);
        vm.expectRevert("Only admin can set new admin");
        game.setAdmin(newAdmin);
    }

    function test_RevertWhen_SetAdminZeroAddress() public {
        vm.expectRevert("Admin cannot be zero address");
        game.setAdmin(address(0));
    }

    function testWithdrawFees() public {
        // First create and complete a game to generate fees
        gameId = createAndJoinGame();

        // Play a full game to generate fees
        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Rock);
        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Scissors);
        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Rock);

        // Calculate expected fees
        uint256 totalBet = BET_AMOUNT * 2;
        uint256 expectedFees = (totalBet * PROTOCOL_FEE_PERCENT) / 100;

        // Verify accumulated fees
        assertEq(game.accumulatedFees(), expectedFees);

        // Withdraw fees
        uint256 adminBalanceBefore = address(this).balance;

        vm.expectEmit(true, false, false, true);
        emit FeeWithdrawn(address(this), expectedFees);

        game.withdrawFees(0); // 0 means withdraw all

        // Verify admin received fees
        assertEq(address(this).balance - adminBalanceBefore, expectedFees);
        assertEq(game.accumulatedFees(), 0);
    }

    function testWithdrawSpecificFees() public {
        // First create and complete a game to generate fees
        gameId = createAndJoinGame();

        // Play a full game to generate fees
        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Rock);
        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Scissors);
        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Rock);

        // Calculate expected fees
        uint256 totalBet = BET_AMOUNT * 2;
        uint256 expectedFees = (totalBet * PROTOCOL_FEE_PERCENT) / 100;
        uint256 withdrawAmount = expectedFees / 2; // Withdraw half

        // Withdraw partial fees
        uint256 adminBalanceBefore = address(this).balance;

        game.withdrawFees(withdrawAmount);

        // Verify admin received correct amount
        assertEq(address(this).balance - adminBalanceBefore, withdrawAmount);
        assertEq(game.accumulatedFees(), expectedFees - withdrawAmount);
    }

    function test_RevertWhen_WithdrawFeesNonAdmin() public {
        vm.prank(playerA);
        vm.expectRevert("Only admin can withdraw fees");
        game.withdrawFees(0);
    }

    function test_RevertWhen_WithdrawMoreThanAvailableFees() public {
        // Create some fees
        gameId = createAndJoinGame();
        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Rock);
        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Scissors);
        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Rock);

        uint256 availableFees = game.accumulatedFees();

        vm.expectRevert("Insufficient fee balance");
        game.withdrawFees(availableFees + 1);
    }

    // ==================== EDGE CASES ====================

    function testCancelGame() public {
        // Create a game
        vm.prank(playerA);
        gameId = game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Cancel the game
        vm.prank(playerA);
        vm.expectEmit(true, false, false, true);
        emit GameCancelled(gameId);

        game.cancelGame(gameId);

        // Verify game state
        RockPaperScissors.Game memory g = game.games(gameId);

        assertEq(uint256(g.state), uint256(RockPaperScissors.GameState.Cancelled));
    }

    function test_RevertWhen_CancelAfterJoin() public {
        gameId = createAndJoinGame();

        vm.prank(playerA);
        vm.expectRevert("Game must be in created state");
        game.cancelGame(gameId);
    }

    function test_RevertWhen_CancelByNonCreator() public {
        // Create a game
        vm.prank(playerA);
        gameId = game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Try to cancel as non-creator
        vm.prank(playerB);
        vm.expectRevert("Only creator can cancel");
        game.cancelGame(gameId);
    }

    function test_RevertWhen_CommitToNonExistentGame() public {
        uint256 nonExistentGameId = 9999;

        vm.prank(playerA);
        vm.expectRevert("Not a player in this game");
        game.commitMove(nonExistentGameId, bytes32("fake commit"));
    }

    function test_RevertWhen_RevealWrongSalt() public {
        gameId = createAndJoinGame();

        // Player A commits
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        // Player B commits
        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // Player A tries to reveal with wrong salt
        bytes32 wrongSalt = keccak256(abi.encodePacked("wrong salt"));

        vm.prank(playerA);
        vm.expectRevert("Hash doesn't match commitment");
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Rock), wrongSalt);
    }

    function test_RevertWhen_RevealInvalidMove() public {
        gameId = createAndJoinGame();

        // Player A commits with valid move
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        // Player B commits
        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // Player A tries to reveal an invalid move (0 or >3)
        vm.prank(playerA);
        vm.expectRevert("Invalid move");
        game.revealMove(gameId, 0, saltA);

        vm.prank(playerA);
        vm.expectRevert("Invalid move");
        game.revealMove(gameId, 4, saltA);
    }

    function test_RevertWhen_RevealTwice() public {
        gameId = createAndJoinGame();

        // Player A commits
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        // Player B commits
        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // Player A reveals
        vm.prank(playerA);
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Rock), saltA);

        // Player A tries to reveal again
        vm.prank(playerA);
        vm.expectRevert("Move already revealed");
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Rock), saltA);
    }

    function testMultiTurnGame() public {
        // Create a 5-turn game
        vm.prank(playerA);
        gameId = game.createGame{value: BET_AMOUNT}(5, TIMEOUT);

        vm.prank(playerB);
        game.joinGame{value: BET_AMOUNT}(gameId);

        // Play 4 turns with player A winning all
        for (uint256 i = 0; i < 4; i++) {
            playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Rock);
            
            // Check scores after each turn
            RockPaperScissors.Game memory g = game.games(gameId);
            assertEq(g.scoreA, i + 1);
            assertEq(g.scoreB, 0);
        }

        // Game should end after turn 3 (majority reached), but let's verify
        // The game actually finishes when a player gets 3 points in a 5-turn game
        // because 3 is majority of 5
    }

    function testGameCounterIncrements() public {
        uint256 initialCounter = game.gameCounter();

        vm.prank(playerA);
        game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        assertEq(game.gameCounter(), initialCounter + 1);

        vm.prank(playerB);
        game.createGame{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        assertEq(game.gameCounter(), initialCounter + 2);
    }

    function testReceiveEth() public {
        // Send ETH directly to contract
        uint256 contractBalanceBefore = address(game).balance;
        uint256 sendAmount = 1 ether;

        (bool success,) = address(game).call{value: sendAmount}("");
        assertTrue(success);

        // Verify contract balance increased
        assertEq(address(game).balance, contractBalanceBefore + sendAmount);
    }

    function testGameStateTransitions() public {
        // Test full state flow
        vm.prank(playerA);
        gameId = game.createGame{value: BET_AMOUNT}(1, TIMEOUT);
        
        RockPaperScissors.Game memory g1 = game.games(gameId);
        assertEq(uint256(g1.state), uint256(RockPaperScissors.GameState.Created));

        vm.prank(playerB);
        game.joinGame{value: BET_AMOUNT}(gameId);
        
        RockPaperScissors.Game memory g2 = game.games(gameId);
        assertEq(uint256(g2.state), uint256(RockPaperScissors.GameState.Created));

        // Commit moves
        bytes32 saltA = keccak256(abi.encodePacked("salt A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));
        vm.prank(playerA);
        game.commitMove(gameId, commitA);
        
        RockPaperScissors.Game memory g3 = game.games(gameId);
        // Still Created because B hasn't committed yet
        assertEq(uint256(g3.state), uint256(RockPaperScissors.GameState.Created));

        bytes32 saltB = keccak256(abi.encodePacked("salt B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));
        vm.prank(playerB);
        game.commitMove(gameId, commitB);
        
        RockPaperScissors.Game memory g4 = game.games(gameId);
        assertEq(uint256(g4.state), uint256(RockPaperScissors.GameState.Committed));

        // Reveal moves
        vm.prank(playerA);
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Rock), saltA);
        
        RockPaperScissors.Game memory g5 = game.games(gameId);
        assertEq(uint256(g5.state), uint256(RockPaperScissors.GameState.Committed));

        vm.prank(playerB);
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Paper), saltB);
        
        RockPaperScissors.Game memory g6 = game.games(gameId);
        assertEq(uint256(g6.state), uint256(RockPaperScissors.GameState.Finished));
    }

    // Test all move combinations
    function testAllMoveCombinations() public {
        // Test all 9 combinations
        RockPaperScissors.Move[3] memory moves = [
            RockPaperScissors.Move.Rock,
            RockPaperScissors.Move.Paper,
            RockPaperScissors.Move.Scissors
        ];

        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 3; j++) {
                // Create new game for each combination
                vm.prank(playerA);
                uint256 currentGameId = game.createGame{value: BET_AMOUNT}(1, TIMEOUT);
                vm.prank(playerB);
                game.joinGame{value: BET_AMOUNT}(currentGameId);

                bytes32 saltA = keccak256(abi.encodePacked("salt A", i, j));
                bytes32 commitA = keccak256(abi.encodePacked(uint8(moves[i]), saltA));

                bytes32 saltB = keccak256(abi.encodePacked("salt B", i, j));
                bytes32 commitB = keccak256(abi.encodePacked(uint8(moves[j]), saltB));

                vm.prank(playerA);
                game.commitMove(currentGameId, commitA);

                vm.prank(playerB);
                game.commitMove(currentGameId, commitB);

                vm.prank(playerA);
                game.revealMove(currentGameId, uint8(moves[i]), saltA);

                uint256 playerABalanceBefore = playerA.balance;
                uint256 playerBBalanceBefore = playerB.balance;

                vm.prank(playerB);
                game.revealMove(currentGameId, uint8(moves[j]), saltB);

                // Check result logic
                if (moves[i] == moves[j]) {
                    // Tie
                    uint256 totalPot = BET_AMOUNT * 2;
                    uint256 fee = (totalPot * PROTOCOL_FEE_PERCENT) / 100;
                    uint256 refundPerPlayer = (totalPot - fee) / 2;
                    assertEq(playerA.balance - playerABalanceBefore, refundPerPlayer);
                    assertEq(playerB.balance - playerBBalanceBefore, refundPerPlayer);
                } else if (
                    (moves[i] == RockPaperScissors.Move.Rock && moves[j] == RockPaperScissors.Move.Scissors) ||
                    (moves[i] == RockPaperScissors.Move.Paper && moves[j] == RockPaperScissors.Move.Rock) ||
                    (moves[i] == RockPaperScissors.Move.Scissors && moves[j] == RockPaperScissors.Move.Paper)
                ) {
                    // Player A wins
                    uint256 expectedPrize = (BET_AMOUNT * 2) * (100 - PROTOCOL_FEE_PERCENT) / 100;
                    assertEq(playerA.balance - playerABalanceBefore, expectedPrize);
                    assertEq(playerB.balance - playerBBalanceBefore, 0);
                } else {
                    // Player B wins
                    uint256 expectedPrize = (BET_AMOUNT * 2) * (100 - PROTOCOL_FEE_PERCENT) / 100;
                    assertEq(playerA.balance - playerABalanceBefore, 0);
                    assertEq(playerB.balance - playerBBalanceBefore, expectedPrize);
                }
            }
        }
    }

    receive() external payable {
        // Allow the test contract to receive ETH
    }
}