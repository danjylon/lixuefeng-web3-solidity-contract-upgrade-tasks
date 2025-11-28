// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {SwapRouter} from "../src/MetaNodeSwap/SwapRouter.sol";

contract SwapRouterScript is Script {
    SwapRouter public swapRouter;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // PoolManager合约地址：0xbE55ABB99Da16dF6b5B0789f6AFB0Fb204903957
        //forge script script/SwapRouter.s.sol:SwapRouterScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
        // 合约地址0xcb93fa575c59aD3F8bCB3FDC100689FCea9498CE
        swapRouter = new SwapRouter(0xbE55ABB99Da16dF6b5B0789f6AFB0Fb204903957);

        vm.stopBroadcast();
    }
}
