// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/RockPaperScissors.sol";

contract DeployScript is Script {
    function run() external {
        // Get private key from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying from address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the contract
        RockPaperScissors game = new RockPaperScissors();
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Successful ===");
        console.log("RockPaperScissors deployed at:", address(game));
        console.log("Admin address:", game.adminAddress());
        console.log("Minimum bet:", game.minBet() / 1e18, "ETH");
        console.log("Join timeout:", game.joinTimeout() / 3600, "hours");
    }
}