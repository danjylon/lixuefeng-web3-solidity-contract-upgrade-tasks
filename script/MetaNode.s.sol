// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {MetaNodeToken} from "../src/MetaNodeStake/MetaNode.sol";

contract MetaNodeScript is Script {
    MetaNodeToken public metaNode;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // forge script script/MetaNode.s.sol:MetaNodeScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
        // 合约地址0xc8F09446541471881477629d2dB0AbdC2C1F05Ea
        metaNode = new MetaNodeToken();

        vm.stopBroadcast();
    }
}
