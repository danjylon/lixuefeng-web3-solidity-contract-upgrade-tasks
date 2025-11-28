// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MetaNodeStake} from "../src/MetaNodeStake/MetaNodeStake.sol";
import {MetaNodeToken} from "../src/MetaNodeStake/MetaNode.sol";
import {MyToken} from "../src/MetaNodeStake/MyToken.sol";
import {console} from "forge-std/console.sol";
//forge test --match-test test_MetaNodeStakeTest -vv
contract MetaNodeStakeTest is Test {
    MetaNodeStake public metaNodeStake;
    MetaNodeToken public metaNode;
    MyToken public myToken;
    address owner = address(this);
    address user1 = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    address user2 = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
    uint256 constant DECIMALS = 1e18;

    function setUp() public {
        myToken = new MyToken("MyToken", "MT");
        metaNode = new MetaNodeToken();
        metaNodeStake = new MetaNodeStake();
        // 挖矿区块从0到500
        metaNodeStake.initialize(metaNode, owner, 0, 500, 10*DECIMALS);
        vm.prank(owner);
        metaNode.approve(address(metaNodeStake), type(uint256).max);
        // // 给 owner 分配 2000 ETH
        vm.deal(owner, 2000 ether);
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        console.log("MetaSwapTest.owner.eth balance: ", owner.balance/DECIMALS);
        console.log("MetaSwapTest.user1.eth balance: ", user1.balance/DECIMALS);
        console.log("MetaSwapTest.user2.eth balance: ", user2.balance/DECIMALS);
        bool success = myToken.transfer(user1, 1e7 * DECIMALS);
        success = myToken.transfer(user2, 1e7 * DECIMALS);
        console.log("MetaSwapTest.owner.myToken balance: ", myToken.balanceOf(owner)/DECIMALS);
        console.log("MetaSwapTest.user1.myToken balance: ", myToken.balanceOf(user1)/DECIMALS);
        console.log("MetaSwapTest.user2.myToken balance: ", myToken.balanceOf(user2)/DECIMALS);
    }

    function test_MetaNodeStakeTest() public {
        console.log("myToken: ", address(myToken));
        console.log("metaNode: ", address(metaNode));
        console.log("metaNodeStake: ", address(metaNodeStake));
        // owner添加eth池子
        // eth地址、权重10、最小质押量100eth、解质押等待区块100、更新收益
        metaNodeStake.addPool(address(0x0), 10, 100*DECIMALS, 100, true);
        // owner添加myToken池子 
        // myToken地址、权重10、最小质押量100万、解质押等待区块100、更新收益
        metaNodeStake.addPool(address(myToken), 10, 1e6*DECIMALS, 100, true);
        console.log("metaNodeStake.pool.length", metaNodeStake.poolLength());

        //user1质押200eth
        vm.prank(user1);
        metaNodeStake.depositETH{value: 200 * DECIMALS}();
        //user1质押200万myToken
        vm.prank(user1);
        myToken.approve(address(metaNodeStake), type(uint256).max);
        vm.prank(user1);
        metaNodeStake.deposit(1, 2e6*DECIMALS);

        //user2质押500eth
        vm.prank(user2);
        metaNodeStake.depositETH{value: 500 * DECIMALS}();
        //user2质押500万myToken
        vm.prank(user2);
        myToken.approve(address(metaNodeStake), type(uint256).max);
        vm.prank(user2);
        metaNodeStake.deposit(1, 5e6*DECIMALS);

        uint256 user1EthStakeBalance = metaNodeStake.stakingBalance(0, user1);
        console.log("user1EthStakeBalance: ", user1EthStakeBalance/DECIMALS);
        uint256 user1MyTokenStakeBalance = metaNodeStake.stakingBalance(1, user1);
        console.log("user1MyTokenStakeBalance: ", user1MyTokenStakeBalance/DECIMALS);

        uint256 user2EthStakeBalance = metaNodeStake.stakingBalance(0, user2);
        console.log("user2EthStakeBalance: ", user2EthStakeBalance/DECIMALS);
        uint256 user2MyTokenStakeBalance = metaNodeStake.stakingBalance(1, user2);
        console.log("user2MyTokenStakeBalance: ", user2MyTokenStakeBalance/DECIMALS);
        // 前进100个区块
        vm.roll(block.number + 100);

        // 计算下当前的质押总收益
        console.log("block.number: ", block.number);
        console.log("MetaNodePerBlock: ", metaNodeStake.MetaNodePerBlock());
        uint256 allProfit = metaNodeStake.getMultiplier(0, block.number);
        console.log("allProfit: ", allProfit/DECIMALS);

        uint256 user1EthStakeProfit = metaNodeStake.pendingMetaNode(0, user1);
        uint256 user2EthStakeProfit = metaNodeStake.pendingMetaNode(0, user2);
        uint256 user1MyTokenStakeProfit = metaNodeStake.pendingMetaNode(1, user1);
        uint256 user2MyTokenStakeProfit = metaNodeStake.pendingMetaNode(1, user2);
        // 由于eth质押和myToken质押的池子的权重是一样的，所以，eth质押收益和myToken质押收益相同
        console.log("user1EthStakeProfit: ", user1EthStakeProfit/DECIMALS);
        console.log("user1MyTokenStakeProfit: ", user1MyTokenStakeProfit/DECIMALS);

        console.log("user2EthStakeProfit: ", user2EthStakeProfit/DECIMALS);
        console.log("user2MyTokenStakeProfit: ", user2MyTokenStakeProfit/DECIMALS);
        //
        // metaNodeStake.updatePool();
        // user1提交解质押请求，解压100个eth
        vm.prank(user1);
        metaNodeStake.unstake(0, 100*DECIMALS);
        // 前进100个区块
        vm.roll(block.number + 100);
        // user1提现100eth
        vm.prank(user1);
        metaNodeStake.withdraw(0);
        // 查询metaNodeStake合约的挖矿收益余额
        console.log("metaNodeStake.balance", metaNode.balanceOf(address(metaNodeStake)));
        // user1提现挖矿收益
        vm.prank(user1);
        metaNodeStake.claim(0);
        console.log("user1EthStakeBalance: ", metaNodeStake.stakingBalance(0, user1)/DECIMALS);
        console.log("user1EthBalance: ", user1.balance/DECIMALS);
        // 前进100个区块
        vm.roll(block.number + 100);
        console.log("user1EthStakeProfit: ", metaNodeStake.pendingMetaNode(0, user1)/DECIMALS);
        console.log("user1MyTokenStakeProfit: ", metaNodeStake.pendingMetaNode(1, user1)/DECIMALS);
        console.log("user1.metaNode.balance: ", metaNode.balanceOf(user1)/DECIMALS);
    }
}
