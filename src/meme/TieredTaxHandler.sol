// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// import "ITaxHandler.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
/**
 * @title 分级税率处理器
 * @dev 根据不同交易类型应用不同税率
 */
contract TieredTaxHandler is Ownable {
    uint256 public constant BASIS_POINTS = 10000;
    
    // 不同交易类型的税率
    uint256 public constant POOL_TRANSFER_TAX = 200;  // 2% 流动性池交易
    uint256 public constant REGULAR_TRANSFER_TAX = 500; // 5% 普通转账
    uint256 public constant WHITELIST_TAX = 100;     // 1% 白名单交易
    // 持有时间相关配置
    uint256 public constant HOLDING_PERIOD_THRESHOLD = 30 days;
    uint256 public constant LONG_TERM_HOLDING_TAX = 300; // 3% 长期持有优惠税率
    // 用户首次购买时间记录
    mapping(address => uint256) public firstPurchaseTime;
    // 限制一次最大转账数量 100万枚
    uint256 public constant LARGEST_TRANSFER_AMOUNT_THRESHOLD = 1000000 * 10**18;
    // 限制一次转账超过50万枚后税率增高
    uint256 public constant HIGH_TRANSFER_AMOUNT_THRESHOLD = 500000 * 10**18;

    address public treasury;
    
    // 白名单地址（DEX池、特定合约等）
    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isPool;
    address[] public pools;
    
    constructor(address _treasury) Ownable(msg.sender) {
        treasury = _treasury;
    }

    function getTax(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) public view returns (uint256) {
        uint256 taxRate = _calculateTaxRate(benefactor, beneficiary, amount);
        console.log("taxRate: ", taxRate);
        return (amount * taxRate) / BASIS_POINTS;
    }
    
    function _calculateTaxRate(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) internal view returns (uint256) {
        // 白名单交易享受优惠税率
        if (isWhitelisted[benefactor] || isWhitelisted[beneficiary]) {
            return WHITELIST_TAX;
        }
        
        // 流动性池交易特殊税率
        if (isPool[benefactor] || isPool[beneficiary]) {
            return POOL_TRANSFER_TAX;
        }
        
        // 长期持有者优惠
        if (_isLongTermHolder(benefactor)) {
            return LONG_TERM_HOLDING_TAX;
        }
        
        // 大额交易惩罚
        if (amount > HIGH_TRANSFER_AMOUNT_THRESHOLD) {
            return REGULAR_TRANSFER_TAX + 200; // 大额交易加2%税
        }
        
        // 默认普通转账税率
        return REGULAR_TRANSFER_TAX;
    }
    
    function _isLongTermHolder(address holder) public  view returns (bool) {
        uint256 firstPurchase = firstPurchaseTime[holder];
        if (firstPurchase == 0) return false;
        
        return block.timestamp - firstPurchase >= HOLDING_PERIOD_THRESHOLD;
    }
    
    // 记录用户首次购买时间（需要在代币转账时调用）
    function recordFirstPurchase(address user) internal {
        if (firstPurchaseTime[user] == 0) {
            firstPurchaseTime[user] = block.timestamp;
        }
    }

    function addWhitelist(address account) external onlyOwner {
        isWhitelisted[account] = true;
    }

    function removeWhitelist(address account) external onlyOwner {
        isWhitelisted[account] = false;
    }

    function addBlacklist(address account) external onlyOwner {
        isBlacklisted[account] = true;
    }

    function removeBlacklist(address account) external onlyOwner {
        isBlacklisted[account] = false;
    }
    
    function addPool(address pool) external onlyOwner {
        isPool[pool] = true;
        pools.push(pool);
    }

    function removePool(address pool) external onlyOwner {
        isPool[pool] = false;
        for (uint i = 0; i < pools.length - 1; i++) {
            if(pools[i] == pool){
                pools[i] = pools[pools.length-1];
                pools[pools.length-1] = pool;
                break;
            }
        }
        pools.pop();
    }
}