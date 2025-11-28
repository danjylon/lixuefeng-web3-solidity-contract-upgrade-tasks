// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {MyMeMeToken} from "../src/meme/MyMeMe.sol";

contract MyMeMeScript is Script {
    MyMeMeToken public myMeMe;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // forge script script/MyMeMe.s.sol:MyMeMeScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
        // 合约地址0xE918e4104b28dE3c081e1B02890ba938422dc5b2
        myMeMe = new MyMeMeToken();

        vm.stopBroadcast();
    }
}
