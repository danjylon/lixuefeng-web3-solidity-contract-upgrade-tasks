// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {MetaNodeStake} from "../src/MetaNodeStake/MetaNodeStake.sol";
import {MetaNodeToken} from "../src/MetaNodeStake/MetaNode.sol";
import {console} from "forge-std/console.sol";

contract MetaNodeStakeScript is Script {
    MetaNodeStake public metaNodeStake;
    // 配置参数
    address constant META_NODE_TOKEN = 0xc8F09446541471881477629d2dB0AbdC2C1F05Ea;
    address constant META_NODE_OWNER = 0xe8114304D54BEC0D7D49277fCf44dA791C9071BD;
    uint256 constant START_BLOCK_DELAY = 5;      // 延迟5个区块开始
    uint256 constant DURATION_BLOCKS = 144 * 30;   // 30天
    uint256 constant REWARD_PER_BLOCK = 10 * 1e18; // 每个区块10个代币

    function setUp() public {}

    function run() public {
        // forge script script/MetaNodeStake.s.sol:MetaNodeStakeScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
        // 合约地址0x52F5FBbe068B1F90ee580Fe692255e6772Ad8b6c
        //cast send --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY 0x52F5FBbe068B1F90ee580Fe692255e6772Ad8b6c "initialize(IERC20,address,uint256,uint256,uint256)" 0xe8114304D54BEC0D7D49277fCf44dA791C9071BD
        vm.startBroadcast();
        metaNodeStake = new MetaNodeStake();
        vm.stopBroadcast();
    }
}
