// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Rock Paper Scissors - Minimal Version
 * @dev Basic single-round game
 */
contract RockPaperScissors {
    enum Move { None, Rock, Paper, Scissors }
    
    struct Game {
        address playerA;
        address playerB;
        uint256 bet;
        bytes32 commitA;
        bytes32 commitB;
        Move moveA;
        Move moveB;
        bool finished;
    }
    
    mapping(uint256 => Game) public games;
    uint256 public gameCounter;
    address public admin;
    uint256 public constant minBet = 0.01 ether;
    
    event GameCreated(uint256 indexed gameId, address indexed creator, uint256 bet);
    event PlayerJoined(uint256 indexed gameId, address indexed player);
    event GameFinished(uint256 indexed gameId, address winner, uint256 prize);
    
    constructor() {
        admin = msg.sender;
    }
    
    function createGame() external payable returns (uint256) {
        require(msg.value >= minBet, "Bet too small");
        
        uint256 gameId = gameCounter++;
        games[gameId] = Game({
            playerA: msg.sender,
            playerB: address(0),
            bet: msg.value,
            commitA: bytes32(0),
            commitB: bytes32(0),
            moveA: Move.None,
            moveB: Move.None,
            finished: false
        });
        
        emit GameCreated(gameId, msg.sender, msg.value);
        return gameId;
    }
    
    function joinGame(uint256 _gameId) external payable {
        Game storage game = games[_gameId];
        require(!game.finished, "Game finished");
        require(game.playerB == address(0), "Already joined");
        require(msg.value == game.bet, "Bet must match");
        
        game.playerB = msg.sender;
        emit PlayerJoined(_gameId, msg.sender);
    }
    
    function commitMove(uint256 _gameId, bytes32 _commitHash) external {
        Game storage game = games[_gameId];
        require(!game.finished, "Game finished");
        
        if (msg.sender == game.playerA) {
            require(game.commitA == bytes32(0), "Already committed");
            game.commitA = _commitHash;
        } else {
            require(msg.sender == game.playerB, "Not a player");
            require(game.commitB == bytes32(0), "Already committed");
            game.commitB = _commitHash;
        }
    }
    
    function revealMove(uint256 _gameId, uint8 _move, bytes32 _salt) external {
        Game storage game = games[_gameId];
        require(!game.finished, "Game finished");
        require(_move >= 1 && _move <= 3, "Invalid move");
        
        Move move = Move(_move);
        bytes32 commit = keccak256(abi.encodePacked(move, _salt));
        
        if (msg.sender == game.playerA) {
            require(commit == game.commitA, "Invalid reveal");
            require(game.moveA == Move.None, "Already revealed");
            game.moveA = move;
        } else {
            require(msg.sender == game.playerB, "Not a player");
            require(commit == game.commitB, "Invalid reveal");
            require(game.moveB == Move.None, "Already revealed");
            game.moveB = move;
        }
        
        if (game.moveA != Move.None && game.moveB != Move.None) {
            _finishGame(_gameId);
        }
    }
    
    function _finishGame(uint256 _gameId) private {
        Game storage game = games[_gameId];
        game.finished = true;
        
        address winner;
        if (game.moveA == game.moveB) {
            // Tie - split pot
            _handleTie(_gameId);
            return;
        } else if (
            (game.moveA == Move.Rock && game.moveB == Move.Scissors) ||
            (game.moveA == Move.Paper && game.moveB == Move.Rock) ||
            (game.moveA == Move.Scissors && game.moveB == Move.Paper)
        ) {
            winner = game.playerA;
        } else {
            winner = game.playerB;
        }
        
        uint256 prize = game.bet * 2;
        (bool success, ) = winner.call{value: prize}("");
        require(success, "Transfer failed");
        
        emit GameFinished(_gameId, winner, prize);
    }
    
    function _handleTie(uint256 _gameId) private {
        Game storage game = games[_gameId];
        uint256 refund = game.bet;
        
        (bool successA, ) = game.playerA.call{value: refund}("");
        (bool successB, ) = game.playerB.call{value: refund}("");
        require(successA && successB, "Transfer failed");
        
        emit GameFinished(_gameId, address(0), 0);
    }
    
    receive() external payable {}
}