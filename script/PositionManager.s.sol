// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {PositionManager} from "../src/MetaNodeSwap/PositionManager.sol";

contract PositionManagerScript is Script {
    PositionManager public positionManager;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // PoolManager合约地址：0xbE55ABB99Da16dF6b5B0789f6AFB0Fb204903957
        // forge script script/PositionManager.s.sol:PositionManagerScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
        // 合约地址0x14E2c005eC429644AE3eEb9f9713D6692Ff5794a
        positionManager = new PositionManager(0xbE55ABB99Da16dF6b5B0789f6AFB0Fb204903957);

        vm.stopBroadcast();
    }
}
