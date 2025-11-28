// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {ERC20} from "./ERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "ITaxHandler.sol";
// import {FixedTaxHandler} from "FixedTaxHandler.sol";
// import {DynamicTaxHandler} from "DynamicTaxHandler.sol";
import {TieredTaxHandler} from "./TieredTaxHandler.sol";
import {console} from "forge-std/console.sol";
// import {BokkyPooBahsDateTimeLibrary} from "./BokkyPooBahsDateTimeLibrary.sol";
// import {Strings} from "@openzeppelin/contracts/utils/Strings.sol"; 
/**
 * @title 
 * @author 
 * @notice 
 * 代币税功能：实现交易税机制，对每笔代币交易征收一定比例的税费，并将税费分配给特定的地址或用于特定的用途。
 * 流动性池集成：设计并实现与流动性池的交互功能，支持用户向流动性池添加和移除流动性。
 * 交易限制功能：设置合理的交易限制，如单笔交易最大额度、每日交易次数限制等，防止恶意操纵市场。
 */
contract MyMeMeToken is Ownable, ERC20, TieredTaxHandler {
    // 这是一个 Solidity 中的语法糖，将 Strings 库中的函数绑定到 uint256 类型上，使得所有 uint256 变量都可以直接调用这些函数
    // 未使用语法糖，string memory idStr = Strings.toString(tokenId);
    // 使用后，string memory idStr = tokenId.toString(); // 更简洁
    // using Strings for uint256; 
    // 每日交易限制5次
    uint256 public dailyTradeLimit = 5;

    // 记录每个用户的交易次数
    mapping(address => uint8) public dailyTradeCount;
    
    // 记录每个用户的最后交易时间（时间戳）
    mapping(address => uint256) public lastTradeTime;

    constructor() ERC20("MyMeMeToken", "MYMEME") TieredTaxHandler(address(this)) {
        _mint(msg.sender, 10000000000*1e18); // 发行100亿
        // 记录用户首次获得代币的时间
        recordFirstPurchase(msg.sender);
    }

    // 重写erc20的transfer, token.transfer(to, amount)，将msg.sender的代币转给to地址
    function transfer(
        address to,
        uint256 value
    ) public override returns (bool){
        // address owner = _msgSender(); // Context合约
        address owner = msg.sender;
        
        (uint256 tax, uint256 netAmount) = _beforeTokenTransfer(owner, to, value );
        // uint256 netAmount = value - tax;
        // 执行转账逻辑
        _transfer(owner, to, netAmount);
        
        // 将税款转账给税务接收地址
        // 这里不能把treasury设为address(0), erc20合约往address(0)转账报错
        if (tax > 0) {
            _transfer(owner, treasury, tax);
        }
        _afterTokenTransfer(owner, to, netAmount);
        return true;
    }

    // token.transferFrom(from, to, amount)，msg.sender将from的代币转给to地址，前提是from将代币approve给msg.sender
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        // console.log("MyMeMeToken.transferFrom.from: ", from);
        // console.log("MyMeMeToken.transferFrom.to: ", to);
        // console.log("MyMeMeToken.transferFrom.value: ", value);
        // address spender = _msgSender();
        address spender = msg.sender;
        _spendAllowance(from, spender, value);
        (uint256 tax, uint256 netAmount) = _beforeTokenTransfer(from, to, value );
        
        // 计算税务
        // uint256 tax = getTax(from, to, value);
        console.log("MyMeMeToken.transferFrom.tax: ", tax);
        // uint256 netAmount = value - tax;
        console.log("MyMeMeToken.transferFrom.netAmount: ", netAmount);
        _transfer(from, to, netAmount);

        // 将税款转账给税务接收地址
        if (tax > 0) {
            _transfer(from, treasury, tax);
        }
        _afterTokenTransfer(from, to, netAmount);
        return true;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount 
    ) internal returns (uint256, uint256){
        // 未添加任何交易对，仅允许所有者操作
        if(pools.length == 0){
            require(from == owner() || to == owner(), "trading is not started");
            // return作用是，未添加任何交易对时，owner的所有转账的交易税、单次交易量、交易次数这些都不用管
            return (0, amount);
        }
        // 黑名单用户不能交易
        require(!isBlacklisted[to] && !isBlacklisted[from], "Blacklisted");
        // 如果是dex交易，单次交易量不能超过100万枚
        if(isPool[from] || isPool[to]) {
            require(amount <= LARGEST_TRANSFER_AMOUNT_THRESHOLD, "exceed largest transfer amount per transaction");
        } 
        // 计算税务
        uint256 tax = getTax(from, to, amount);
        uint256 netAmount = amount - tax;
        // 如果是dex交易，每日买卖总次数限制为5次
        if(isPool[from] && !isPool[to]){
            // 如果是dex交易，发送方是交易对，接收方是钱包地址，即买，to就是买家
            // 如果用户从未交易过，或最后交易已超过24小时
            if (lastTradeTime[to] == 0 || block.timestamp - lastTradeTime[to] >= 1 days) {
                // 重置该用户的交易计数
                dailyTradeCount[to] = 0;
            }
            require(dailyTradeCount[to]<= dailyTradeLimit, "transaction limit");
        } else if (!isPool[from] && isPool[to]) {
            // 如果是dex交易，接收方是交易对，即from是卖家
            // 问题：此时由于有交易税，卖家在支付交易所相应金额的同时，要多付交易税，即原本的转账金额+额外交易税，而不是交易所得到的是支付金额扣税后的数量
            // 如果用户从未交易过，或最后交易已超过24小时
            if (lastTradeTime[from] == 0 || block.timestamp - lastTradeTime[from] >= 1 days) {
                // 重置该用户的交易计数
                dailyTradeCount[from] = 0;
            }
            require(dailyTradeCount[from]<= dailyTradeLimit, "transaction limit");
            netAmount = amount;
        }
        require(balanceOf(from) >= tax+netAmount, "insufficient balance");
        return (tax, netAmount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        // if(!isPool[to]) {
        //     // 如果接收者不是交易对，即一般钱包之间的转账或者从交易所买币
        //     // 记录用户首次获得代币的时间
            recordFirstPurchase(to);
        // } 
        // 未添加任何交易对，仅允许所有者操作
        if(pools.length == 0){
            // return作用是，未添加任何交易对时，所有的交易税、单次交易量、交易次数这些都不用管
            return;
        }
        if(isPool[from] && !isPool[to]){
            // 如果是dex交易，发送方是交易对，接收方是钱包地址，即买，to就是买家
            // 更新交易计数和时间
            dailyTradeCount[to]++;
            lastTradeTime[to] = block.timestamp;
        } else if (!isPool[from] && isPool[to]) {
            // 如果是dex交易，接收方是交易对，即from是卖家
            // 更新交易计数和时间
            dailyTradeCount[from]++;
            lastTradeTime[from] = block.timestamp;
        }
    }

    // 允许所有者调整每日交易限制次数
    function setDailyTradeLimit(uint256 newLimit) external onlyOwner{
        dailyTradeLimit = newLimit;
    }
}