// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MyMeMeToken} from "../src/meme/MyMeMe.sol";
import {console} from "forge-std/console.sol";

contract MyMeMeTest is Test {
    MyMeMeToken public myMeMe;
    address owner = address(this);
    address user1 = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    address user2 = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);

    function setUp() public {
        myMeMe = new MyMeMeToken();
    }

    function test_BalanceOf() public {
        uint256 balance = myMeMe.balanceOf(owner);
        console.log("balance: ", balance/1e18);
        // 设置当前时间为部署后150秒（超过锁定期）
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        bool success = myMeMe.transfer(user1, 1e9 * 1e18);
        console.log(success);
        console.log("balanceOfUser1: ", myMeMe.balanceOf(user1)/1e18);
        console.log("timestamp: ", block.timestamp);
        console.log("firstPurchaseTime(owner): ", myMeMe.firstPurchaseTime(owner));
        console.log("firstPurchaseTime(user1): ", myMeMe.firstPurchaseTime(user1));
    }

}
