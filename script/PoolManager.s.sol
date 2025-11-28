// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {PoolManager} from "../src/MetaNodeSwap/PoolManager.sol";

contract PoolManagerScript is Script {
    PoolManager public poolManager;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // forge script script/PoolManager.s.sol:PoolManagerScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
        // 问题，验证失败
        // forge verify-contract 0xbE55ABB99Da16dF6b5B0789f6AFB0Fb204903957 src/MetaNodeSwap/PoolManager.sol:PoolManager --chain 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --rpc-url $SEPOLIA_RPC_URL --compiler-version 0.8.25 --watch
        poolManager = new PoolManager();

        vm.stopBroadcast();
    }
}
