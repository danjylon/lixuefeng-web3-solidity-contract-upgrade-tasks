// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

// import {IERC20} from "../meme/IERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FullMath} from "./libraries/FullMath.sol";
import {SqrtPriceMath} from "./libraries/SqrtPriceMath.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {LiquidityMath} from "./libraries/LiquidityMath.sol";
import {LowGasSafeMath} from "./libraries/LowGasSafeMath.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {SwapMath} from "./libraries/SwapMath.sol";
import {FixedPoint128} from "./libraries/FixedPoint128.sol";

import {IPool, IMintCallback, ISwapCallback} from "./interfaces/IPool.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {console} from "forge-std/console.sol";
/**
 * 一切的基础，不用部署该合约，会在PoolManager中以new的方式创建
 */
contract Pool is IPool {
    using SafeCast for uint256;
    using LowGasSafeMath for int256;
    using LowGasSafeMath for uint256;

    /// IPool，immutable表示该变量在合约部署后不可更改
    // 与constant不同，immutable变量可以在构造函数中赋值，而不仅限于编译时确定
    address public immutable override factory;
    ///  IPool
    address public immutable override token0;
    ///  IPool
    address public immutable override token1;
    ///  IPool
    uint24 public immutable override fee;
    ///  IPool
    int24 public immutable override tickLower;
    ///  IPool
    int24 public immutable override tickUpper;

    ///  IPool
    uint160 public override sqrtPriceX96;
    ///  IPool
    int24 public override tick;
    ///  IPool
    uint128 public override liquidity;

    ///  IPool
    uint256 public override feeGrowthGlobal0X128;
    ///  IPool
    uint256 public override feeGrowthGlobal1X128;

    struct Position {
        // 该 Position 拥有的流动性
        uint128 liquidity;
        // 可提取的 token0 数量
        uint128 tokensOwed0;
        // 可提取的 token1 数量
        uint128 tokensOwed1;
        // 手续费收取的是token，卖哪种token，手续费就是这种token
        // 上次提取手续费时的 feeGrowthGlobal0X128
        uint256 feeGrowthInside0LastX128;
        // 上次提取手续费是的 feeGrowthGlobal1X128
        uint256 feeGrowthInside1LastX128;
    }

    // 用一个 mapping 来存放所有 Position 的信息
    mapping(address => Position) public positions;

    function getPosition(
        address owner
    )
        external
        view
        override
        returns (
            uint128 _liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        return (
            positions[owner].liquidity,
            positions[owner].feeGrowthInside0LastX128,
            positions[owner].feeGrowthInside1LastX128,
            positions[owner].tokensOwed0,
            positions[owner].tokensOwed1
        );
    }

    constructor() {
        // constructor 中初始化 immutable 的常量
        // Factory 创建 Pool 时会通 new Pool{salt: salt}() 的方式创建 Pool 合约，通过 salt 指定 Pool 的地址，这样其他地方也可以推算出 Pool 的地址
        // 参数通过读取 Factory 合约的 parameters 获取
        // 不通过构造函数传入，因为 CREATE2 会根据 initcode 计算出新地址（new_address = hash(0xFF, sender, salt, bytecode)），带上参数就不能计算出稳定的地址了
        // 这里获取到的factory, token0, token1, tickLower, tickUpper, fee直接给Pool合约的factory, token0, token1, tickLower, tickUpper, fee赋值了
        (factory, token0, token1, tickLower, tickUpper, fee) = IFactory(
            msg.sender 
        ).parameters();//PoolManager继承了Factory，在PoolManager中调用createPool时，new Pool()会调用这里的constructor，msg.sender是PoolManager合约，所以IFactory(msg.sender)相当于实例化了PoolManager，再调用PoolManager的parameters()得到参数
    }
    
    // 将pool中的sqrtPriceX96设为传入的sqrtPriceX96_
    function initialize(uint160 sqrtPriceX96_) external override {
        require(sqrtPriceX96 == 0, "INITIALIZED");
        // 通过价格获取 tick，
        tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96_);
        // 判断 tick 是否在 tickLower 和 tickUpper 之间
        require(
            tick >= tickLower && tick < tickUpper,
            "sqrtPriceX96 should be within the range of [tickLower, tickUpper)"
        );
        // 初始化 Pool 的 sqrtPriceX96，sqrtPrice: 代表交易对价格的平方根，X96表示该平方根左移96位，即乘以2^96，
        // 在 Uniswap V3 中，价格定义为 token1/token0 的比率（1 个 token0 可兑换多少 token1）
        // Uniswap V3 的恒定乘积公式需要使用价格的平方根进行计算，使用平方根可使价格在 ticks（刻度）上均匀分布
        // Solidity 不支持浮点数，需要使用整数表示小数，2^96 的放大系数提供了足够高的精度，同时避免精度损失，最终存储为 uint160 类型（20 字节），平衡了精度和存储效率
        // 优势：计算高效、精度高、Gas友好
        // tick = log(sqrtPriceX96)
        sqrtPriceX96 = sqrtPriceX96_;
    }

    struct ModifyPositionParams {
        // the address that owns the position
        address owner;
        // any change in liquidity
        int128 liquidityDelta;
    }

    function _modifyPosition(
        ModifyPositionParams memory params
    ) private returns (int256 amount0, int256 amount1) {
        // 通过新增的流动性计算 amount0 和 amount1
        // 参考 UniswapV3 的代码
        // 根据当前价格和最高价格
        amount0 = SqrtPriceMath.getAmount0Delta(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickUpper),
            params.liquidityDelta
        );
        //根据当前价格和最低价格
        amount1 = SqrtPriceMath.getAmount1Delta(
            TickMath.getSqrtPriceAtTick(tickLower),
            sqrtPriceX96,
            params.liquidityDelta
        );
        Position storage position = positions[params.owner]; // msg.sender是PositionManager

        // 提取手续费，计算从上一次提取到当前的手续费
        uint128 tokensOwed0 = uint128(
            FullMath.mulDiv( // 全局交易费（每个单位流动性的交易费，会变）减去你的交易对中的交易费，乘以流动性
                feeGrowthGlobal0X128 - position.feeGrowthInside0LastX128,
                position.liquidity,
                FixedPoint128.Q128
            )
        );
        uint128 tokensOwed1 = uint128(
            FullMath.mulDiv(
                feeGrowthGlobal1X128 - position.feeGrowthInside1LastX128,
                position.liquidity,
                FixedPoint128.Q128
            )
        );

        // 更新提取手续费的记录，同步到当前最新的 feeGrowthGlobal0X128，代表都提取完了
        // 你取了一次了，就会把当前的交易费更新到你的交易对的交易费
        position.feeGrowthInside0LastX128 = feeGrowthGlobal0X128;
        position.feeGrowthInside1LastX128 = feeGrowthGlobal1X128;
        // 把可以提取的手续费记录到 tokensOwed0 和 tokensOwed1 中
        // LP 可以通过 collect 来最终提取到用户自己账户上
        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            position.tokensOwed0 += tokensOwed0;
            position.tokensOwed1 += tokensOwed1;
        }

        // 修改 liquidity，全局流动性会根据交易对流动性的变化而变化
        liquidity = LiquidityMath.addDelta(liquidity, params.liquidityDelta);
        position.liquidity = LiquidityMath.addDelta(
            position.liquidity,
            params.liquidityDelta
        );
    }

    /// @dev Get the pool's balance of token0
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    // 获取token0的余额
    function balance0() private view returns (uint256) {
        // 通过abi引入IERC20接口的balanceOf方法，减小代码量，降低gas花费
        (bool success, bytes memory data) = token0.staticcall( // staticcall表示调用的方法是view方法，节省gas
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(this))
        );
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    /// @dev Get the pool's balance of token1
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    // 获取token1的余额
    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) = token1.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(this))
        );
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    // 添加流动性
    function mint(
        address recipient, //该流动性的提供者
        uint128 amount, //要添加的流动性，可根据amount算出要添加的token0和token1的数量
        bytes calldata data //回调时要用的参数
    ) external override returns (uint256 amount0, uint256 amount1) { // 返回token0和token1的数量
        require(amount > 0, "Mint amount must be greater than 0");
        // 基于 amount 计算出当前需要多少 amount0 和 amount1
        (int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: recipient,
                liquidityDelta: int128(amount)
            })
        );
        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        console.log("pool.mint.amount0: ", amount0/1e18);
        console.log("pool.mint.amount1: ", amount1/1e18);

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        // 回调 mintCallback
        //LP 需要在这个回调方法中将对应的代币转入到 Pool 合约中，所以调用 Pool 合约 mint 方法的也是一个合约PositionManager，并且在该合约中定义好 mintCallback 方法。 
        IMintCallback(msg.sender).mintCallback(amount0, amount1, data);
        // 验证流动性提供者的token0和token1有没有转给PositionManager，mint方法的调用者是PositionManager，
        if (amount0 > 0)
            require(balance0Before.add(amount0) <= balance0(), "M0");
        if (amount1 > 0)
            require(balance1Before.add(amount1) <= balance1(), "M1");

        emit Mint(msg.sender, recipient, amount, amount0, amount1);
    }

    // 收回代币
    function collect(
        address recipient, //接收人
        uint128 amount0Requested, //token0的数量
        uint128 amount1Requested //token1的数量
    ) external override returns (uint128 amount0, uint128 amount1) {
        // 获取当前用户的 position
        Position storage position = positions[msg.sender]; // msg.sender是PositionManager

        // 把钱退给用户 recipient
        amount0 = amount0Requested > position.tokensOwed0
            ? position.tokensOwed0
            : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1
            ? position.tokensOwed1
            : amount1Requested;
        // 问题，为什么不直接使用IERC20的transfer方法
        if (amount0 > 0) {
            console.log("pool.collect.position.tokensOwed0: ", position.tokensOwed0);
            console.log("pool.collect.amount0: ", amount0);
            position.tokensOwed0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
            // bool success = IERC20(token0).transfer(recipient, amount0);
            // require(success, "Transfer failed");
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
            // bool success = IERC20(token1).transfer(recipient, amount1);
            // require(success, "Transfer failed");
        }

        emit Collect(msg.sender, recipient, amount0, amount1);
    }

    // 移除流动性
    function burn(
        uint128 amount //要移除的流动性数量，根据amount算出移除的token0和token1数量
    ) external override returns (uint256 amount0, uint256 amount1) {
        require(amount > 0, "Burn amount must be greater than 0");
        require(
            amount <= positions[msg.sender].liquidity,
            "Burn amount exceeds liquidity"
        );
        // 修改 positions 中的信息
        (int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: msg.sender,
                liquidityDelta: -int128(amount) //移除流动性，所以这里是负数
            })
        );
        // 获取燃烧后的 amount0 和 amount1
        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);
        // 将移除的token0和token1的数量加到该流动性提供者的token0和token1的数量上，这里只是记录，并没有真正把token0和token1返给流动性提供者，调用collect时才发送给流动性提供者
        if (amount0 > 0 || amount1 > 0) {
            (
                positions[msg.sender].tokensOwed0,
                positions[msg.sender].tokensOwed1
            ) = (
                positions[msg.sender].tokensOwed0 + uint128(amount0),
                positions[msg.sender].tokensOwed1 + uint128(amount1)
            );
        }

        emit Burn(msg.sender, amount, amount0, amount1);
    }

    // 交易中需要临时存储的变量
    struct SwapState {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the global fee growth of the input token
        uint256 feeGrowthGlobalX128;
        // token0买token1时，amountIn表示token0，token1买token0时，amountIn表示token1，amountIn始终表示花出的token数量
        uint256 amountIn;
        // token0买token1时，amountOut表示token1，token1买token0时，amountOut表示token0，amountOut始终表示买到的token数量
        uint256 amountOut;
        // 该交易中的手续费，如果 zeroForOne 是 ture，则是用户转入 token0，单位是 token0 的数量，反之是 token1 的数量
        uint256 feeAmount;
    }

    // 代币交易
    function swap(
        address recipient, //交易人
        bool zeroForOne, // 是否用token0买token1，是true，即用token0买token1，否false，即用token1买token0
        int256 amountSpecified, //买方提供的代币数量，amountSpecified>0表示，给出花的token数量，计算能买到的token数量，amountSpecified<0表示，给出买到的token数量，计算要花多少token
        uint160 sqrtPriceLimitX96, //限制的价格，当用token0买token1时，要求价格要大于sqrtPriceLimitX96，当用token1买token0时，要求价格要小于sqrtPriceLimitX96
        bytes calldata data // 回调函数的参数
    ) external override returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, "AS");

        // zeroForOne: 如果从 token0 交换 token1 则为 true，从 token1 交换 token0 则为 false
        // 判断当前价格是否满足交易的条件
        console.log("pool.swap.sqrtPriceLimitX96: ",sqrtPriceLimitX96);
        console.log("pool.swap.sqrtPriceX96: ",sqrtPriceX96);
        console.log("pool.swap.sqrtPriceLimitX96 > sqrtPriceX96: ", sqrtPriceLimitX96 > sqrtPriceX96);
        console.log("pool.swap.sqrtPriceLimitX96 < TickMath.MAX_SQRT_PRICE: ", sqrtPriceLimitX96 < TickMath.MAX_SQRT_PRICE);
        require(
            // 总公式：价格sqrtPriceX96，价格永远是token1/token0
            zeroForOne
                // 如果用token0买token1，价格sqrtPriceX96就是token1/token0，token1数量就是token0*sqrtPriceX96，sqrtPriceX96变大，获得的token1就变大
                // 所以要求sqrtPriceX96越大越好，
                ? sqrtPriceLimitX96 < sqrtPriceX96 && 
                    sqrtPriceLimitX96 > TickMath.MIN_SQRT_PRICE //sqrtPriceLimitX96越低越好，但也要有一个下限TickMath.MIN_SQRT_PRICE
                // 如果用token1买token0，token0的数量=token1/sqrtPriceX96，sqrtPriceX96越小，获得的token0就越多
                // 所以要求sqrtPriceX96越小越好
                : sqrtPriceLimitX96 > sqrtPriceX96 &&
                    sqrtPriceLimitX96 < TickMath.MAX_SQRT_PRICE, //sqrtPriceLimitX96越高越好，但也要有一个上限TickMath.MAX_SQRT_PRICE
            "SPL"
        );

        // amountSpecified 大于 0，表示用户给出要花的token数量，计算出买到的token数量，amountSpecified<0，表示用户给出要买的token的数量，计算出要花多少token
        bool exactInput = amountSpecified > 0; 
        console.log("pool.exactInput: ", exactInput);

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified, // 你提供的代币数量中还有多少没有换成另一种代币
            amountCalculated: 0, // 已经兑换完成的另一种代币的数量
            sqrtPriceX96: sqrtPriceX96, // 当前价格
            feeGrowthGlobalX128: zeroForOne //费率，token0买token1，收的手续费是token0，费率就是feeGrowthGlobal0X128，token1买token0，费率就是feeGrowthGlobal1X128，
                ? feeGrowthGlobal0X128
                : feeGrowthGlobal1X128,
            amountIn: 0, // token0买token1时，amountIn是花出的token0数量，token1买token0时，amountIn是花出的token1数量，
            amountOut: 0, // token0买token1时，amountOut是买到的token1数量，token1买token0时，amountOut是买到的token0数量
            feeAmount: 0 // 支付的手续费，token0买token1的话，该费用使用token0结算，token1买token0时，该费用使用token1结算
        });

        // 计算交易的上下限，基于 tick 计算价格
        uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(tickUpper);
        // 计算用户交易价格的限制，如果是 zeroForOne 是 true，说明用户会换入 token0，会压低 token0 的价格（也就是池子的价格），所以要限制最低价格不能超过 sqrtPriceX96Lower
        uint160 sqrtPriceX96PoolLimit = zeroForOne 
            // 总公式：价格sqrtPriceX96就是token1/token0
            // 当用token0买token1时，pool中的token0变多，token1变少，那么sqrtPriceX96就会降低，那么就要规定一下sqrtPriceX96的下限
            ? sqrtPriceX96Lower
            // 当用token1买token0时，pool中的token0变少，token1变多，那么sqrtPriceX96就会涨高，那么就要规定一下sqrtPriceX96的上限
            : sqrtPriceX96Upper;

        // 计算交易的具体数值SwapState，完成这笔交易后，pool中该交易对的价格就变了
        (
            state.sqrtPriceX96,
            state.amountIn,
            state.amountOut,
            state.feeAmount
        ) = SwapMath.computeSwapStep(
            sqrtPriceX96, //当前价格
            (
                zeroForOne
                    ? sqrtPriceX96PoolLimit < sqrtPriceLimitX96
                    : sqrtPriceX96PoolLimit > sqrtPriceLimitX96
            )
                ? sqrtPriceLimitX96
                : sqrtPriceX96PoolLimit,
            liquidity,
            amountSpecified,
            fee
        );

        // 更新新的价格
        sqrtPriceX96 = state.sqrtPriceX96;
        tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);

        // 计算手续费
        state.feeGrowthGlobalX128 += FullMath.mulDiv(
            state.feeAmount,
            FixedPoint128.Q128,
            liquidity
        );

        // 更新手续费相关信息
        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
        }

        // 计算交易后用户手里的 token0 和 token1 的数量
        if (exactInput) { 
            // amountSpecified > 0，给出要花的token数量，计算能买的token数量
            // pool中剩余没花的token数量，花了amountIn的token的数量，手续费也是使用要花出的token支付
            state.amountSpecifiedRemaining -= (state.amountIn + state.feeAmount)
                .toInt256();
            // 已经买到的token的数量，用负数表示0-amountOut，<0
            state.amountCalculated = state.amountCalculated.sub(
                state.amountOut.toInt256()
            );
        } else { 
            // amountSpecified < 0，给出要买的token的数量，计算要花的token数量
            // pool中剩余的要买的token数量（负数），已经买到的token的数量amountOut（正数）
            state.amountSpecifiedRemaining += state.amountOut.toInt256();
            // 已经花出的token数量
            state.amountCalculated = state.amountCalculated.add(
                (state.amountIn + state.feeAmount).toInt256()
            );
        }
        // amount0表示token0的数量，amount1表示token1的数量
        (amount0, amount1) = zeroForOne == exactInput
            ? ( 
                // 提供要花多少，计算能买多少，输入固定，输出不固定
                // zeroForOne==true且exactInput==true 或 zeroForOne==false且exactInput==false
                // token0买token1，且给出token0计算出能买到多少token1，或token1买token0，且给出token1，计算能买到多少token0
                // 此时amountSpecified表示给出的token0数量，amountSpecifiedRemaining表示还有多少token0没有兑换成token1
                amountSpecified - state.amountSpecifiedRemaining, //>=0
                // 此时amountCalculated表示已经买到的token1的数量
                state.amountCalculated //<0
            )
            : (
                // 通过要买多少，计算要花多少，输出固定，输入不固定
                // zeroForOne==true且exactInput==false 或 zeroForOne==false且exactInput==true
                // token0买token1，但给出的是token1的数量，计算要花多少token0
                // token1买token0，给出的是token0的数量，计算要花多少token1
                state.amountCalculated, // <0
                amountSpecified - state.amountSpecifiedRemaining //>=0
            );
        console.log("pool.swap.amount0: ", amount0);
        console.log("pool.swap.amount1: ", amount1);
        if (zeroForOne) {
            // token0买token1，amount1就是买到的token1
            // 此时pool得到amount0，转出amount1，所以amount0是正的，amount1是负的（代表支出）
            // callback 中需要给 Pool 转入 token
            uint256 balance0Before = balance0();
            console.log("pool.swap.balance0Before: ", balance0Before);
            // swap方法由SwapRouter调用，然后回调SwapRouter自己的swapCallback方法
            // 将要花费的token0转到pool合约中
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);
            require(balance0Before.add(uint256(amount0)) <= balance0(), "IIA");

            // 转 Token 给用户
            // 将买到的amount1数量的token1转给买家，
            if (amount1 < 0) 
                TransferHelper.safeTransfer(
                    token1,
                    recipient,
                    uint256(-amount1) 
                );
        } else {
            // token1买token0，amount0就是买到的token0
            // 此时pool得到amount1，转出amount0，所以amount0是负的，amount1是正的
            // callback 中需要给 Pool 转入 token
            uint256 balance1Before = balance1();
            console.log("pool.swap.balance1Before: ", balance1Before);
            // swap方法由SwapRouter调用，然后回调SwapRouter自己的swapCallback方法
            // 将要花费的token1转到pool合约中
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);
            require(balance1Before.add(uint256(amount1)) <= balance1(), "IIA");

            // 转 Token 给用户
            // 将买到的amount0数量的token0转给买家
            if (amount0 < 0)
                TransferHelper.safeTransfer(
                    token0,
                    recipient,
                    uint256(-amount0)
                );
        }

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            sqrtPriceX96,
            liquidity,
            tick
        );
    }
}
