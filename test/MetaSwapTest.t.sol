// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "../src/MetaNodeSwap/PoolManager.sol";
import {PositionManager} from "../src/MetaNodeSwap/PositionManager.sol";
import {SwapRouter} from "../src/MetaNodeSwap/SwapRouter.sol";
import {console} from "forge-std/console.sol";
import {MyMeMeToken} from "../src/meme/MyMeMe.sol";
import {WETH} from "../src/meme/WETH.sol";
import {IPoolManager} from "../src/MetaNodeSwap/interfaces/IPoolManager.sol";
import {IPositionManager} from "../src/MetaNodeSwap/interfaces/IPositionManager.sol";
import {ISwapRouter} from "../src/MetaNodeSwap/interfaces/ISwapRouter.sol";
import {TickMath} from "../src/MetaNodeSwap/libraries/TickMath.sol";
// forge test --match-test test_MetaSwapTest -vv
contract MetaSwapTest is Test {
    PoolManager public poolManager;
    PositionManager public positionManager;
    SwapRouter public swapRouter;
    MyMeMeToken public myMeMe;
    WETH public weth;
    address owner = address(this);
    address  user1 = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    address  user2 = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
    // 只有 address payable 类型才能被强制转换为具有 payable fallback 的合约类型
    address payable constant WETH_ADDRESS = payable(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);
    uint256 constant DECIMALS = 1e18;

    function setUp() public {
        // 使用new是部署
        poolManager = new PoolManager();
        positionManager = new PositionManager(address(poolManager));
        swapRouter = new SwapRouter(address(poolManager));
        myMeMe = new MyMeMeToken();
        // 部署 WETH 到指定地址 WETH_ADDRESS
        vm.etch(WETH_ADDRESS, type(WETH).runtimeCode);
        // 使用 合约名称(address) 只是一个类型转换，即把一个合约地址转换为一个合约实例，而能够使用 合约实例.函数() 的前提是该合约已部署
        weth = WETH(WETH_ADDRESS); // 这里只是创建了一个WETH的实例，与WETH的部署没有关系，需要把WETH部署到本地
    }

    function test_MetaSwapTest() public {
        console.log("MetaSwapTest.poolManager: ", address(poolManager));
        console.log("MetaSwapTest.positionManager: ", address(positionManager));
        console.log("MetaSwapTest.swapRouter: ", address(swapRouter));
        console.log("MetaSwapTest.myMeMe: ", address(myMeMe));
        console.log("MetaSwapTest.owner: ", owner);
        console.log("MetaSwapTest.myMeMe.balance: ", myMeMe.balanceOf(owner)/DECIMALS);
        console.log("MetaSwapTest.myMeMe.owner() == owner: ", myMeMe.owner() == owner);
        // // 给 owner 分配 2000 ETH
        vm.deal(owner, 2000 ether);
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        console.log("MetaSwapTest.eth balance: ", owner.balance/DECIMALS);

        // WETH_ADDRESS.transfer(1500*DECIMALS);
        // (bool success, ) = WETH_ADDRESS.call{value: 1500*DECIMALS}(""); //the amount you wanna transfer is in the {}, and in the (), you can pass a function with name of string
        // require(success, "Call failed");
        // 调用的前提是，1：WETH已部署，2：weth创建了WETH的实例
        vm.prank(owner);
        weth.deposit{value: 1500 ether}();
        vm.prank(user1);
        weth.deposit{value: 500 ether}();
        vm.prank(user2);
        weth.deposit{value: 500 ether}();

        // uint256 wethAmount = 1500 * DECIMALS;
        // // 部署 WETH 到指定地址
        // vm.etch(WETH_ADDRESS, type(WETH).runtimeCode);
        // // 给 owner 分配 1000 WETH
        // deal(WETH_ADDRESS, owner, wethAmount);
        console.log("MetaSwapTest.owner eth balance: ", owner.balance/DECIMALS);
        console.log("MetaSwapTest.owner wethBalance: ", weth.balanceOf(owner)/DECIMALS);
        console.log("MetaSwapTest.user1 eth balance: ", user1.balance/DECIMALS);
        console.log("MetaSwapTest.user1 wethBalance: ", weth.balanceOf(user1)/DECIMALS);
        console.log("MetaSwapTest.user2 eth balance: ", user2.balance/DECIMALS);
        console.log("MetaSwapTest.user2 wethBalance: ", weth.balanceOf(user2)/DECIMALS);
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
        address token0;
        address token1;
        if(address(myMeMe) > WETH_ADDRESS) {
            token1 = address(myMeMe);
            token0 = WETH_ADDRESS;
        } else {
            token0 = address(myMeMe);
            token1 = WETH_ADDRESS;
        }
        console.log("MetaSwapTest.token1: ", token1);
        if(token1 == address(myMeMe)){
            // MYMEME是token1，Weth是token0，1000000/1 = 1e6
            sqrtPriceX96 = uint160(1000 << 96);
            // tick = floor(log(price)/log(1.0001))
            /*
            几个关键 tick 值:
            price: 1 -> tick: 0
            price: 10 -> tick: +23026
            price: 100 -> tick: +46052
            price: 1e6 -> tick: +138629
            price: 0.1 -> tick: -23026
            price: 0.01 -> tick: -46052
            price: 1e-6 -> tick: -138629
            */
            tickLower = 130000;
            tickUpper = 150000;
        } else {
            // Weth是token1，MYMEME是token0，1/1000000 = 1e-6
            uint256 shifted = 1 << 96;
            sqrtPriceX96 = uint160(shifted / 1000);
            // tick = floor(log(price)/log(1.0001))
            tickLower = -150000;
            tickUpper = -130000;
        }
        console.log("MetaSwapTest.sqrtPriceX96: ", sqrtPriceX96);

        // 创建池子
        IPoolManager.CreateAndInitializeParams memory params = IPoolManager.CreateAndInitializeParams({
            token0: token0,
            token1: token1, // weth
            fee:3000, //0.3%
            // tick = Math.floor(Math.log(price) / Math.log(1.0001));
            // tick = floor(log(price)/log(1.0001))
            tickLower: tickLower,
            tickUpper: tickUpper,
            // 价格计算是按token1/token0
            // 所以对于MYMEME/WETH对，如果1000000MYMEME=1WETH
            // 如果MYMEME地址大于Weth，即MYMEME是token1，Weth是token0，那么price就是MYMEME / WETH = 1000000
            // 如果MYMEME地址小于Weth，即Weth是token1，MYMEME是token0，那么price就是WETH / MYMEME = 1 / 1000000 = 1e-6
            // 价格是MYMEME/ETH，，即MYMEME/ETH=0.000001，则使用√(price) × 2^96 （即<< 96）
            sqrtPriceX96: sqrtPriceX96
        });
        address poolAddress = poolManager.createAndInitializePoolIfNecessary(params);
        console.log("MetaSwapTest.poolAddress: ", poolAddress);
        IPoolManager.PoolInfo[] memory poolsInfo = poolManager.getAllPools();
        console.log("MetaSwapTest.poolsInfo: ", poolsInfo.length);
        console.log("MetaSwapTest.pool: ", poolsInfo[0].pool);
        console.log("MetaSwapTest.token0: ", poolsInfo[0].token0);
        console.log("MetaSwapTest.token1: ", poolsInfo[0].token1);
        console.log("MetaSwapTest.index: ", poolsInfo[0].index);
        console.log("MetaSwapTest.feeProtocol: ", poolsInfo[0].feeProtocol);
        console.log("MetaSwapTest.tickLower: ", poolsInfo[0].tickLower);
        console.log("MetaSwapTest.tickUpper: ", poolsInfo[0].tickUpper);
        console.log("MetaSwapTest.tick: ", poolsInfo[0].tick);
        console.log("MetaSwapTest.liquidity: ", poolsInfo[0].liquidity);

        address poolAddress2 = poolManager.getPool(address(myMeMe),WETH_ADDRESS,0);
        console.log("MetaSwapTest.poolAddress2: ", poolAddress2);

        // 添加流动性
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams({
            token0: token0, // MyMeMeToken
            token1: token1, // weth
            index: 0,
            amount0Desired: 1e9 *DECIMALS, // 添加1亿枚mymeme
            amount1Desired: 1e3 *DECIMALS, // 添加100枚weth
            recipient: owner,
            deadline: block.timestamp + 3600
        });
        // 将owner的代币授权给positionManager，代币转移由positionManager进行操作，将owner的代币转给pool合约的地址
        bool success = myMeMe.approve(address(positionManager), type(uint256).max);
        console.log("MetaSwapTest.success: ", success);
        success = weth.approve(address(positionManager), type(uint256).max);
        console.log("MetaSwapTest.success: ", success);

        (
            uint256 positionId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = positionManager.mint(mintParams);
        console.log("MetaSwapTest.positionId: ", positionId);
        console.log("MetaSwapTest.liquidity: ", liquidity);
        console.log("MetaSwapTest.amount0: ", amount0/DECIMALS);
        console.log("MetaSwapTest.amount1: ", amount1/DECIMALS);

        // address ownerOfPosition = positionManager.ownerOf(1);
        // assertEq(ownerOfPosition, owner);
        // // 刚添加流动性就移除流动性
        // (amount0, amount1) = positionManager.burn(positionId);
        // console.log("MetaSwapTest.mymeme:amount0: ", amount0);
        // console.log("MetaSwapTest.weth:amount1: ", amount1);
        // console.log("MetaSwapTest.balance1: ", myMeMe.balanceOf(owner)/DECIMALS);

        // console.log("MetaSwapTest.myMeMe.balanceOf(poolAddress): ", myMeMe.balanceOf(poolAddress));
        // console.log("MetaSwapTest.weth.balanceOf(poolAddress): ", weth.balanceOf(poolAddress));

        // // 收回代币
        // (amount0, amount1) = positionManager.collect(positionId, owner);
        // console.log("MetaSwapTest.amount0: ", amount0);
        // console.log("MetaSwapTest.amount1: ", amount1);
        // console.log("MetaSwapTest.balance2: ", myMeMe.balanceOf(owner)/DECIMALS);

        // owner将池子的地址加入mymeme合约中
        vm.prank(owner);
        myMeMe.addPool(poolAddress);

        // 询价，指定要花的token数量
        uint32[] memory indexPath = new uint32[](1);
        indexPath[0] = 0;

        // 使用极值作为价格限制
        uint160 sqrtPriceLimitX96;
        // 现在是token1买token0，即weth买mymeme
        bool zeroForOne = false; // token0买token1 true，token1买token0 false

        if (zeroForOne) {
            // 如果用 token0 买 token1，设置最低价格限制，即sqrtPriceLimitX96越小越好
            sqrtPriceLimitX96 = TickMath.MIN_SQRT_PRICE + 1;
        } else {
            // 如果用 token1 买 token0，设置最高价格限制，即sqrtPriceLimitX96越大越好
            sqrtPriceLimitX96 = TickMath.MAX_SQRT_PRICE - 1;
        }

        ISwapRouter.QuoteExactInputParams memory quoteExactInputParams = ISwapRouter.QuoteExactInputParams({
            tokenIn: WETH_ADDRESS, // 用weth买mymeme，输入weth查询能买多少mymeme
            tokenOut: address(myMeMe),
            indexPath: indexPath,
            amountIn: 1e18, // 查询1weth能买多少mymeme
            sqrtPriceLimitX96: sqrtPriceLimitX96 //token1买token0，要求sqrtPriceLimitX96越大越好
        });
        // user1 询价，花1weth，能买多少mymeme
        vm.prank(user1);
        uint256 amountOut = swapRouter.quoteExactInput(quoteExactInputParams) ;
        console.log("MetaSwapTest.quoteExactInput.mymeme.amountOut: ", amountOut/DECIMALS); // 经计算，1weth能买996556个mymeme
        
        ISwapRouter.ExactInputParams memory exactInputParams = ISwapRouter.ExactInputParams({
            tokenIn: WETH_ADDRESS,
            tokenOut: address(myMeMe),
            indexPath: indexPath,
            recipient: user1,
            deadline: block.timestamp + 1 hours,
            amountIn: 1e18, 
            amountOutMinimum: amountOut * 9900/10000, // 滑点设置为1%，计算能买到多少时往下计算
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });
        // 将weth授权给swapRouter
        vm.prank(user1);
        weth.approve(address(swapRouter), type(uint256).max);
        // user1 花1weth购买mymeme
        vm.prank(user1);
        amountOut = swapRouter.exactInput(exactInputParams) ;
        console.log("MetaSwapTest.exactInput.mymeme.amountOut: ", amountOut);
        console.log("MetaSwapTest.user1.weth.balance: ", weth.balanceOf(user1));
        console.log("MetaSwapTest.user1.mymeme.balance: ", myMeMe.balanceOf(user1));

        ISwapRouter.QuoteExactOutputParams memory quoteExactOutputParams = ISwapRouter.QuoteExactOutputParams({
            tokenIn: WETH_ADDRESS, // 用weth买mymeme，输入mymeme查询要花多少weth
            tokenOut: address(myMeMe),
            indexPath: indexPath,
            amountOut: 1e6 * DECIMALS, //查询要买100万个mymeme，要花多少weth
            sqrtPriceLimitX96: sqrtPriceLimitX96 //token1买token0，要求sqrtPriceLimitX96越大越好
        });
        // user2 询价，买100百万个mymeme，花多少weth
        vm.prank(user2);
        uint256 amountIn = swapRouter.quoteExactOutput(quoteExactOutputParams) ;
        console.log("MetaSwapTest.quoteExactOutput.weth.amountIn: ", amountIn); //经计算，买100万个mymeme，要花1.004351494288736976 weth

        ISwapRouter.ExactOutputParams memory exactOutputParams = ISwapRouter.ExactOutputParams({
            tokenIn: WETH_ADDRESS, // 用weth买mymeme，输入mymeme查询要花多少weth
            tokenOut: address(myMeMe),
            indexPath: indexPath,
            amountOut: 1e6 * DECIMALS, //查询要买100万个mymeme，要花多少weth
            recipient: user2,
            deadline: block.timestamp + 1 hours,
            amountInMaximum: amountIn * 10100/10000, // 滑点设置为1%，计算要花多少时，往上计算
            sqrtPriceLimitX96: sqrtPriceLimitX96 //token1买token0，要求sqrtPriceLimitX96越大越好
        });
        // 将weth授权给swapRouter
        vm.prank(user2);
        weth.approve(address(swapRouter), type(uint256).max);
        // user2 购买1百万mymeme
        vm.prank(user2);
        amountIn = swapRouter.exactOutput(exactOutputParams) ;
        console.log("MetaSwapTest.exactOutput.weth.amountIn: ", amountIn);
        console.log("MetaSwapTest.user2.weth.balance: ", weth.balanceOf(user2));
        console.log("MetaSwapTest.user2.mymeme.balance: ", myMeMe.balanceOf(user2));


        // 现在是token0买token1，即mymeme买weth
        zeroForOne = true; // token0买token1 true，token1买token0 false
        // zeroForOne = true, 如果用 token0 买 token1，设置最低价格限制，即sqrtPriceLimitX96越小越好
        // zeroForOne = false, 如果用 token1 买 token0，设置最高价格限制，即sqrtPriceLimitX96越大越好
        sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        quoteExactInputParams = ISwapRouter.QuoteExactInputParams({
            tokenIn: address(myMeMe), // 用mymeme买weth，输入mymeme查询能买多少weth
            tokenOut: WETH_ADDRESS,
            indexPath: indexPath,
            amountIn: 5e5*DECIMALS, // 查询50万mymeme能买多少weth
            sqrtPriceLimitX96: sqrtPriceLimitX96 //token0买token1，要求sqrtPriceLimitX96越小越好
        });
        // user1 询价，花50万mymeme，能买多少weth
        vm.prank(user1);
        amountOut = swapRouter.quoteExactInput(quoteExactInputParams) ;
        console.log("MetaSwapTest.quoteExactInput.weth.amountOut: ", amountOut); // 经计算，花50万个mymeme，能买0.499279112642406558weth
        
        exactInputParams = ISwapRouter.ExactInputParams({
            tokenIn: address(myMeMe),
            tokenOut: WETH_ADDRESS,
            indexPath: indexPath,
            recipient: user1,
            deadline: block.timestamp + 1 hours,
            amountIn: 5e5*DECIMALS, 
            amountOutMinimum: amountOut * 9900/10000, // 滑点设置为1%，计算能买到多少时往下计算
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });
        // 将mymeme授权给swapRouter
        vm.prank(user1);
        myMeMe.approve(address(swapRouter), type(uint256).max);
        // user1 用50万mymeme购买weth
        vm.prank(user1);
        amountOut = swapRouter.exactInput(exactInputParams) ;
        console.log("MetaSwapTest.exactInput.weth.amountOut: ", amountOut);
        console.log("MetaSwapTest.user1.mymeme.balance: ", myMeMe.balanceOf(user1));
        console.log("MetaSwapTest.user1.weth.balance: ", weth.balanceOf(user1));

        quoteExactOutputParams = ISwapRouter.QuoteExactOutputParams({
            tokenIn: address(myMeMe), // 用mymeme买eth，输入weth查询要花多少mymeme
            tokenOut: WETH_ADDRESS,
            indexPath: indexPath,
            amountOut: 5e17, //查询要买0.5个weth，要花多少mymeme
            sqrtPriceLimitX96: sqrtPriceLimitX96 //token0买token1，要求sqrtPriceLimitX96越小越好
        });

        // user2 询价，买0.5个weth，花多少mymeme
        vm.prank(user2);
        amountIn = swapRouter.quoteExactOutput(quoteExactOutputParams) ;
        console.log("MetaSwapTest.quoteExactOutput.mymeme.amountIn: ", amountIn); //经计算，买0.5个weth，要花mymeme

        exactOutputParams = ISwapRouter.ExactOutputParams({
            tokenIn: address(myMeMe), // 用mymeme买weth，输入mymeme查询要花多少weth
            tokenOut: WETH_ADDRESS,
            indexPath: indexPath,
            amountOut: 5e17, //查询要买0.5个weth，要花多少mymeme
            recipient: user2,
            deadline: block.timestamp + 1 hours,
            amountInMaximum: amountIn * 10100/10000, // 滑点设置为1%，计算要花多少时，往上计算
            sqrtPriceLimitX96: sqrtPriceLimitX96 //token0买token1，要求sqrtPriceLimitX96越小越好
        });
        // 将mymeme授权给swapRouter
        vm.prank(user2);
        myMeMe.approve(address(swapRouter), type(uint256).max);
        // user2 用mymeme买0.5个weth
        vm.prank(user2);
        amountIn = swapRouter.exactOutput(exactOutputParams) ;
        console.log("MetaSwapTest.exactOutput.mymeme.amountIn: ", amountIn);
        console.log("MetaSwapTest.user2.mymeme.balance: ", myMeMe.balanceOf(user2));
        console.log("MetaSwapTest.user2.weth.balance: ", weth.balanceOf(user2));

        // 移除流动性
        console.log("MetaSwapTest.remove lp");
        (amount0, amount1) = positionManager.burn(positionId);
        console.log("MetaSwapTest.mymeme:amount0: ", amount0);
        console.log("MetaSwapTest.weth:amount1: ", amount1);
        console.log("MetaSwapTest.balance1: ", myMeMe.balanceOf(owner)/DECIMALS);

        console.log("MetaSwapTest.myMeMe.balanceOf(poolAddress): ", myMeMe.balanceOf(poolAddress));
        console.log("MetaSwapTest.weth.balanceOf(poolAddress): ", weth.balanceOf(poolAddress));

        // myMeMe先移除pool，不然报错exceed largest transfer amount per transaction
        myMeMe.removePool(poolAddress);
        console.log("MetaSwapTest.owner.weth.balance: ", weth.balanceOf(owner));
        console.log("MetaSwapTest.owner.mymeme.balance: ", myMeMe.balanceOf(owner));
        // 收回代币
        (amount0, amount1) = positionManager.collect(positionId, owner);
        console.log("MetaSwapTest.amount0: ", amount0);
        console.log("MetaSwapTest.amount1: ", amount1);
        console.log("MetaSwapTest.owner.weth.balance: ", weth.balanceOf(owner));
        console.log("MetaSwapTest.owner.mymeme.balance: ", myMeMe.balanceOf(owner));
    }


}
