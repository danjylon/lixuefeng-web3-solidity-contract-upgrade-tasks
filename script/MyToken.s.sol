// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {MyToken} from "../src/MetaNodeStake/MyToken.sol";

contract MyTokenScript is Script {
    MyToken public myToken;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // forge script script/MyToken.s.sol:MyTokenScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
        // 合约地址0x39190e9962ef5418ACA9DBEeDb1D3304566A9eD3
        myToken = new MyToken("MyTokenFoundry", "MTF");

        vm.stopBroadcast();
    }
}
