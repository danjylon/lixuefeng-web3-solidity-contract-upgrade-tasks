# 安装依赖
    forge install foundry-rs/forge-std@v1.11.0
    forge install OpenZeppelin/openzeppelin-contracts@v5.4.0
    forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.4.0
    forge install OpenZeppelin/openzeppelin-foundry-upgrades@v0.4.0
# meme代币+swap
## 单元测试
    forge test --match-test test_MetaSwapTest -vv
    1. 单元测试中进行了weth部署、MyMeMe代币部署、PoolManager部署、PositionManager部署、SwapRouter部署
    2. eth与weth 1:1 兑换
    3. 创建交易对 MyMeMe(token0) <-> weth(token1)
    4. 添加流动性
    5. 交易1: weth(tokenIn) <-> MyMeMe(tokenOut)，提供weth数量计算MyMeMe数量，提供MyMeMe数量计算weth数量
    6. 交易2: MyMeMe(tokenIn) <-> weth(tokenOut)，提供MyMeMe数量计算weth数量，提供weth数量计算MyMeMe数量
    7. 移除流动性
    8. 收回代币
## 部署MyMeMe.sol, 合约地址0xE918e4104b28dE3c081e1B02890ba938422dc5b2
    forge script script/MyMeMe.s.sol:MyMeMeScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
## 部署PoolManager.sol, 合约地址0xbE55ABB99Da16dF6b5B0789f6AFB0Fb204903957
    forge script script/PoolManager.s.sol:PoolManagerScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
## 部署PositionManager.sol, 合约地址0x14E2c005eC429644AE3eEb9f9713D6692Ff5794a
    forge script script/PositionManager.s.sol:PositionManagerScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
## 部署SwapRouter.sol, 合约地址0xcb93fa575c59aD3F8bCB3FDC100689FCea9498CE
    forge script script/SwapRouter.s.sol:SwapRouterScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
# MyToken stake
## 单元测试
    forge test --match-test test_MetaNodeStakeTest -vv
    1. 单元测试中进行了MyToken部署、MetaNodeToken部署、MetaNodeStake部署
    2. MyToken铸造、转账
    3. 创建eth质押池子和MyToken质押池子
    4. 质押eth和MyToken
    5. 查看挖矿收益
    6. 解质押
    7. 收回代笔
    8. 查询挖矿收益MetaNode
## 部署MyToken.sol, 合约地址0x39190e9962ef5418ACA9DBEeDb1D3304566A9eD3
    forge script script/MyToken.s.sol:MyTokenScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
## 部署MetaNodeToken, 合约地址0xc8F09446541471881477629d2dB0AbdC2C1F05Ea
    forge script script/MetaNode.s.sol:MetaNodeScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
## 部署MetaNodeStake, 合约地址0x52F5FBbe068B1F90ee580Fe692255e6772Ad8b6c
    forge script script/MetaNodeStake.s.sol:MetaNodeStakeScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
## MetaNodeStake initialize
    forge script script/MetaNodeStakeInitialize.s.sol:MetaNodeStakeInitializeScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify -vvvv
# foundry学习总结
    文档: foundry.doc

