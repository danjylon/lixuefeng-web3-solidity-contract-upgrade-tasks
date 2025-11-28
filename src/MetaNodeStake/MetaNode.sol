// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MetaNodeToken is ERC20{
    
    constructor() ERC20("MetaNodeToken", "MetaNode"){
        // 初始供应量1千万，或者留空以便之后通过 mint 函数铸造
         _mint(msg.sender, 1e7*1e18);
    }
}