// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;
pragma abicoder v2;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
// import {IERC20} from "../meme/IERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LiquidityAmounts} from "./libraries/LiquidityAmounts.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {FixedPoint128} from "./libraries/FixedPoint128.sol";

import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {console} from "forge-std/console.sol";
/**
 *  想象你是一个外汇做市商：
    你只愿意在 1 美元 = 6.5 ~ 7.0 人民币 的区间内买卖美元。
    当市场价在这个区间内时，你的资金参与交易，赚取手续费。
    如果汇率涨到 7.5 或跌到 6.0，你的资金就“闲置”，不参与交易。
    这个 “只在 6.5~7.0 区间提供美元/人民币流动性”的决策和投入的资金组合，就是一个 头寸。

    在 DeFi 中：
    “汇率” → 代币价格（token1/token0）
    “你的资金” → 存入的 WETH 和 MYMEME
    “区间” → tickLower 到 tickUpper
    “头寸” → 记录这一切的 NFT + 链上数据
 * 头寸是一个nft合约，在添加流动性时，mint一个该合约的nft发给流动性提供者，调用pool合约添加流动性、移除流动性、收回代币
 * Position头寸 = 你在某个流动性池中的投资份额或仓位，添加流动性的过程就是创建头寸的过程
 * 第二部署该合约
    Δx = L * (1/√P - 1/√P_upper)
    Δy = L * (√P - √P_lower)
    其中：
    Δx = token0 的数量
    Δy = token1 的数量
    P = 当前价格
    P_lower, P_upper = 价格区间边界
 */
contract PositionManager is IPositionManager, ERC721 {
    // 保存 PoolManager 合约地址
    IPoolManager public poolManager;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint176 private _nextId = 1;

    constructor(address _poolManger) ERC721("MetaNodeSwapPosition", "MNSP") {
        poolManager = IPoolManager(_poolManger);
    }

    // 用一个 mapping 来存放所有 Position 的信息
    mapping(uint256 => PositionInfo) public positions;

    // 获取全部的 Position 信息
    function getAllPositions()
        external
        view
        override
        returns (PositionInfo[] memory positionInfo)
    {
        positionInfo = new PositionInfo[](_nextId - 1);
        for (uint32 i = 0; i < _nextId - 1; i++) {
            positionInfo[i] = positions[i + 1];
        }
        return positionInfo;
    }

    function getSender() public view returns (address) {
        return msg.sender;
    }

    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    // modifier checkDeadline(uint256 deadline) {
    //     require(_blockTimestamp() <= deadline, "Transaction too old");
    //     _;
    // }
    modifier checkDeadline(uint256 deadline) {
        _checkDeadline(deadline);
        _;
    }
    
    function _checkDeadline(uint256 deadline) internal view {
        require(_blockTimestamp() <= deadline, "Transaction too old");
    }

    // 添加流动性，调用pool合约的mint
    function mint(
        MintParams calldata params
    )
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (
            uint256 positionId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // mint 一个 NFT 作为 position 发给 LP
        // NFT 的 tokenId 就是 positionId
        // 通过 MintParams 里面的 token0 和 token1 以及 index 获取对应的 Pool
        // 调用 poolManager 继承自Factory的 getPool 方法获取 Pool 地址
        address _pool = poolManager.getPool( // 调用factory合约的getPool方法
            params.token0,
            params.token1,
            params.index
        );
        IPool pool = IPool(_pool);

        // 通过获取 pool 相关信息，结合 params.amount0Desired 和 params.amount1Desired 计算这次要注入的流动性

        uint160 sqrtPriceX96 = pool.sqrtPriceX96();
        uint160 sqrtRatioAX96 = TickMath.getSqrtPriceAtTick(pool.tickLower());
        uint160 sqrtRatioBX96 = TickMath.getSqrtPriceAtTick(pool.tickUpper());

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            params.amount0Desired,
            params.amount1Desired
        );

        // data 是 mint 后回调 PositionManager 会额外带的数据
        // 需要 PoistionManger 实现回调，在回调中给 Pool 打钱
        bytes memory data = abi.encode(
            params.token0,
            params.token1,
            params.index,
            msg.sender //问题：谁？如果是MetaSwapTest中，msg.sender是owner，
        );
        // 这里调用pool合约的mint后，计算出需要向pool中添加的两种代币数量，在pool的mint方法中调用该合约的mintCallback方法，把两种代币转移到pool合约中
        (amount0, amount1) = pool.mint(address(this), liquidity, data);

        _mint(params.recipient, (positionId = _nextId++)); // 调用ERC721的_mint接口，铸造一个nft，将该nft发送给recipient，tokenId为positionId

        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            ,

        ) = pool.getPosition(address(this)); //Pool合约的_modifyPosition方法中创建了Position并塞入positions中

        positions[positionId] = PositionInfo({
            id: positionId,
            owner: params.recipient,
            token0: params.token0,
            token1: params.token1,
            index: params.index,
            fee: pool.fee(),
            liquidity: liquidity,
            tickLower: pool.tickLower(),
            tickUpper: pool.tickUpper(),
            tokensOwed0: 0,
            tokensOwed1: 0,
            feeGrowthInside0LastX128: feeGrowthInside0LastX128, // 添加流动性后手续费会变化
            feeGrowthInside1LastX128: feeGrowthInside1LastX128
        });
    }

    // modifier isAuthorizedForToken(uint256 tokenId) {
    //     address owner = ERC721.ownerOf(tokenId);
    //     require(_isAuthorized(owner, msg.sender, tokenId), "Not approved");
    //     _;
    // }

    modifier isAuthorizedForToken(uint256 tokenId) {
        _isAuthorizedForToken(tokenId);
        _;
    }
    
    function _isAuthorizedForToken(uint256 tokenId) internal view {
        address owner = ERC721.ownerOf(tokenId);
        require(_isAuthorized(owner, msg.sender, tokenId), "Not approved");
    }

    // 移除流动性
    function burn(
        uint256 positionId
    )
        external
        override
        isAuthorizedForToken(positionId)
        returns (uint256 amount0, uint256 amount1)
    {
        PositionInfo storage position = positions[positionId];
        // 通过 isAuthorizedForToken 检查 positionId 是否有权限
        // 移除流动性，但是 token 还是保留在 pool 中，需要再调用 collect 方法才能取回 token
        // 通过 positionId 获取对应 LP 的流动性
        uint128 _liquidity = position.liquidity;
        // 调用 Pool 的方法给 LP 退流动性
        address _pool = poolManager.getPool(
            position.token0,
            position.token1,
            position.index
        );
        IPool pool = IPool(_pool);
        (amount0, amount1) = pool.burn(_liquidity);

        // 计算这部分流动性产生的手续费
        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            ,

        ) = pool.getPosition(address(this));
        // 移除的token数量是你添加的流动性的token和你挣到的手续费
        position.tokensOwed0 +=
            uint128(amount0) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 -
                        position.feeGrowthInside0LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );

        position.tokensOwed1 +=
            uint128(amount1) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 -
                        position.feeGrowthInside1LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );

        // 更新 position 的信息
        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        position.liquidity = 0;
    }

    // 收回代币   
    function collect(
        uint256 positionId,
        address recipient
    )
        external
        override
        isAuthorizedForToken(positionId)
        returns (uint256 amount0, uint256 amount1)
    {
        // 通过 isAuthorizedForToken 检查 positionId 是否有权限
        // 调用 Pool 的方法给 LP 退流动性
        PositionInfo storage position = positions[positionId];
        address _pool = poolManager.getPool(
            position.token0,
            position.token1,
            position.index
        );
        IPool pool = IPool(_pool);
        (amount0, amount1) = pool.collect(
            recipient,
            position.tokensOwed0,
            position.tokensOwed1
        );

        // position 已经彻底没用了，销毁
        position.tokensOwed0 = 0;
        position.tokensOwed1 = 0;

        if (position.liquidity == 0) {
            _burn(positionId); // 如果你的流动性全部移除了，你收回代币时会把你添加流动性时铸造的nft也给你burn掉
        }
    }

    // 在Pool合约中mint函数中回调，流动性提供者提供流动性时，计算出token0和token1的数量后，从流动性提供者钱包将相应数量的token0和token1转给池子
    function mintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        // 检查 callback 的合约地址是否是 Pool
        (address token0, address token1, uint32 index, address payer) = abi
            .decode(data, (address, address, uint32, address));
        address _pool = poolManager.getPool(token0, token1, index);
        // 此函数在pool合约中回调，所以msg.sender肯定是pool合约
        require(_pool == msg.sender, "Invalid callback caller");

        // 在这里给 Pool 打钱，需要用户先 approve 足够的金额，这里才会成功
        // 这里mintCallback是在pool合约的mint方法中调用，所以msg.sender就是pool合约
        if (amount0 > 0) {
            console.log("payer: ", payer);
            console.log("msg.sender: ", msg.sender);
            console.log("token0: ", token0);
            console.log("amount0: ", amount0/1e18);
            bool success = IERC20(token0).transferFrom(payer, msg.sender, amount0);
            console.log("positionManager.mintCallback.token0.success: ", success);
            if(!success) {
                revert("amount0 transform failed");
            }
        }
        if (amount1 > 0) {
            console.log("payer: ", payer);
            console.log("msg.sender: ", msg.sender);
            console.log("token1: ", token1);
            console.log("amount1: ", amount1/1e18);
            bool success = IERC20(token1).transferFrom(payer, msg.sender, amount1);
            console.log("positionManager.mintCallback.token1.success: ", success);
            if(!success) {
                revert("amount1 transform failed");
            }
        }
    }
}
