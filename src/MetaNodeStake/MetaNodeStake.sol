// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {console} from "forge-std/console.sol";
contract MetaNodeStake is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;
    using Address for address;
    using Math for uint256;

    // ************************************** INVARIANT **************************************

    bytes32 public constant ADMIN_ROLE = keccak256("admin_role");
    bytes32 public constant UPGRADE_ROLE = keccak256("upgrade_role");

    uint256 public constant ETH_PID = 0; //native token 即eth的专用池子编号
    
    // ************************************** DATA STRUCTURE **************************************
    /*
    Basically, any point in time, the amount of MetaNodes entitled to a user but is pending to be distributed is:

    pending MetaNode = (user.stAmount * pool.accMetaNodePerST) - user.finishedMetaNode

    Whenever a user deposits or withdraws staking tokens to a pool. Here's what happens:
    1. The pool's `accMetaNodePerST` (and `lastRewardBlock`) gets updated.
    2. User receives the pending MetaNode sent to his/her address.
    3. User's `stAmount` gets updated.
    4. User's `finishedMetaNode` gets updated.
    */
    struct Pool {
        // Address of staking token
        address stTokenAddress;
        // Weight of pool，池子所占权重
        uint256 poolWeight;
        // Last block number that MetaNodes distribution occurs for pool，上一次结算收益时的区块
        uint256 lastRewardBlock;
        // Accumulated MetaNodes per staking token of pool，这个池子的每一份stake的代币可以收到的累计质押挖矿token数量
        // stake了1000枚eth或erc20代币，然后池子出块的奖励token总共是10000，那么每份质押也就是每个eth或erc20将得到10个奖励token
        uint256 accMetaNodePerST;
        // Staking token amount，质押的代币数量
        uint256 stTokenAmount;
        // Min staking amount，最小质押数量
        uint256 minDepositAmount;
        // Withdraw locked blocks，提出解质押请求后需要等待的块数
        uint256 unstakeLockedBlocks;
    }
    // 解质押请求
    struct UnstakeRequest {
        // Request withdraw amount，提现的数量
        uint256 amount;
        // The blocks when the request withdraw amount can be released，提出解质押请求时的区块高度+unstakeLockedBlocks
        uint256 unlockBlocks;
    }

    struct User {
        // Staking token amount that user provided
        uint256 stAmount;
        // Finished distributed MetaNodes to user，已经完成结算的token奖励
        uint256 finishedMetaNode;
        // Pending to claim MetaNodes，待提现的奖励
        uint256 pendingMetaNode;
        // Withdraw request list，用户的解质押请求
        UnstakeRequest[] requests;
    }

    // ************************************** STATE VARIABLES **************************************
    // First block that MetaNodeStake will start from，质押挖矿的开始区块
    uint256 public startBlock;
    // First block that MetaNodeStake will end from，质押挖矿的结束区块
    uint256 public endBlock;
    // MetaNode token reward per block，每个质押挖矿区块的token奖励
    uint256 public MetaNodePerBlock;

    // Pause the withdraw function
    bool public withdrawPaused;
    // Pause the claim function
    bool public claimPaused;

    // MetaNode token，奖励质押者的token
    IERC20 public MetaNode;
    // MetaNode token的部署者
    address public metaNodeOwner;

    // Total pool weight / Sum of all pool weights，所有质押池子的权重之和
    uint256 public totalPoolWeight;
    Pool[] public pool; //所有的质押池子

    // pool id => user address => user info
    mapping (uint256 => mapping (address => User)) public user;

    // ************************************** EVENT **************************************

    event SetMetaNode(IERC20 indexed MetaNode);

    event PauseWithdraw();

    event UnpauseWithdraw();

    event PauseClaim();

    event UnpauseClaim();

    event SetStartBlock(uint256 indexed startBlock);

    event SetEndBlock(uint256 indexed endBlock);

    event SetMetaNodePerBlock(uint256 indexed MetaNodePerBlock);

    event AddPool(address indexed stTokenAddress, uint256 indexed poolWeight, uint256 indexed lastRewardBlock, uint256 minDepositAmount, uint256 unstakeLockedBlocks);

    event UpdatePoolInfo(uint256 indexed poolId, uint256 indexed minDepositAmount, uint256 indexed unstakeLockedBlocks);

    event SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 totalPoolWeight);

    event UpdatePool(uint256 indexed poolId, uint256 indexed lastRewardBlock, uint256 totalMetaNode);

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);

    event RequestUnstake(address indexed user, uint256 indexed poolId, uint256 amount);

    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount, uint256 indexed blockNumber);

    event Claim(address indexed user, uint256 indexed poolId, uint256 MetaNodeReward);

    // ************************************** MODIFIER **************************************

    // modifier checkPid(uint256 _pid) {
    //     require(_pid < pool.length, "invalid pid");
    //     _;
    // }
    modifier checkPid(uint256 _pid) {
        _checkPid(_pid);
        _;
    }
    
    function _checkPid(uint256 _pid) internal view {
        require(_pid < pool.length, "invalid pid");
    }

    // modifier whenNotClaimPaused() {
    //     require(!claimPaused, "claim is paused");
    //     _;
    // }
    modifier whenNotClaimPaused() {
        _whenNotClaimPaused();
        _;
    }
    
    function _whenNotClaimPaused() internal view {
        require(!claimPaused, "claim is paused");
    }

    // modifier whenNotWithdrawPaused() {
    //     require(!withdrawPaused, "withdraw is paused");
    //     _;
    // }

    modifier whenNotWithdrawPaused() {
        _whenNotWithdrawPaused();
        _;
    }
    
    function _whenNotWithdrawPaused() internal view {
        require(!withdrawPaused, "withdraw is paused");
    }

    /**
     * @notice Set MetaNode token address. Set basic info when deploying.
     */
    function initialize(
        IERC20 _MetaNode,
        address _metaNodeOwner,
        uint256 _startBlock, //质押挖矿的开始区块
        uint256 _endBlock, //质押挖矿的结束区块
        uint256 _MetaNodePerBlock // 每个区块产生多少个奖励token
    ) public initializer {
        require(_startBlock <= _endBlock && _MetaNodePerBlock > 0, "invalid parameters");

        __AccessControl_init(); // 权限控制初始化
        __UUPSUpgradeable_init(); // uups升级初始化
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADE_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        setMetaNode(_MetaNode); //设置奖励token
        metaNodeOwner = _metaNodeOwner;
        startBlock = _startBlock;
        endBlock = _endBlock;
        MetaNodePerBlock = _MetaNodePerBlock;

    }
    // uups upgradeable的升级必须重写该方法
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADE_ROLE)
        override
    {

    }

    // ************************************** ADMIN FUNCTION **************************************

    /**
     * @notice Set MetaNode token address. Can only be called by admin
     */
    function setMetaNode(IERC20 _MetaNode) public onlyRole(ADMIN_ROLE) {
        MetaNode = _MetaNode;
        // bool success = MetaNode.approve(address(this), type(uint256).max);
        // console.log("setMetaNode.approve: ", success);
        emit SetMetaNode(MetaNode);
    }

    /**
     * @notice Pause withdraw. Can only be called by admin.
     */
    function pauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(!withdrawPaused, "withdraw has been already paused");

        withdrawPaused = true;

        emit PauseWithdraw();
    }

    /**
     * @notice Unpause withdraw. Can only be called by admin.
     */
    function unpauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(withdrawPaused, "withdraw has been already unpaused");

        withdrawPaused = false;

        emit UnpauseWithdraw();
    }

    /**
     * @notice Pause claim. Can only be called by admin.
     */
    function pauseClaim() public onlyRole(ADMIN_ROLE) {
        require(!claimPaused, "claim has been already paused");

        claimPaused = true;

        emit PauseClaim();
    }

    /**
     * @notice Unpause claim. Can only be called by admin.
     */
    function unpauseClaim() public onlyRole(ADMIN_ROLE) {
        require(claimPaused, "claim has been already unpaused");

        claimPaused = false;

        emit UnpauseClaim();
    }

    /**
     * @notice Update staking start block. Can only be called by admin.
     */
    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(_startBlock <= endBlock, "start block must be smaller than end block");

        startBlock = _startBlock;

        emit SetStartBlock(_startBlock);
    }

    /**
     * @notice Update staking end block. Can only be called by admin.
     */
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        require(startBlock <= _endBlock, "start block must be smaller than end block");

        endBlock = _endBlock;

        emit SetEndBlock(_endBlock);
    }

    /**
     * @notice Update the MetaNode reward amount per block. Can only be called by admin.
     */
    function setMetaNodePerBlock(uint256 _MetaNodePerBlock) public onlyRole(ADMIN_ROLE) {
        require(_MetaNodePerBlock > 0, "invalid parameter");

        MetaNodePerBlock = _MetaNodePerBlock;

        emit SetMetaNodePerBlock(_MetaNodePerBlock);
    }

    /**
     * @notice Add a new staking to pool. Can only be called by admin
     * DO NOT add the same staking token more than once. MetaNode rewards will be messed up if you do
     */
    // 质押token的合约地址，池子权重，最小质押量，解质押时需要等待的块数，是否需更新池子收益
    function addPool(address _stTokenAddress, uint256 _poolWeight, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks,  bool _withUpdate) public onlyRole(ADMIN_ROLE) {
        // Default the first pool to be ETH pool, so the first pool must be added with stTokenAddress = address(0x0)
        if (pool.length > 0) {
            // 当已经存在池子时，不能再添加eth的池子
            require(_stTokenAddress != address(0x0), "invalid staking token address");
        } else {
            // 当没有池子时，第一个创建的池子必须是eth的池子
            require(_stTokenAddress == address(0x0), "invalid staking token address");
        }
        // allow the min deposit amount equal to 0
        //require(_minDepositAmount > 0, "invalid min deposit amount");
        require(_unstakeLockedBlocks > 0, "invalid withdraw locked blocks");
        require(block.number < endBlock, "Already ended");

        // 在Pool结构体中有个lastRewardBlock属性，记录上一次结算收益的区块，这里就是将lastRewardBlock这个修改一下，即每添加一个池子，就结算一下所有池子的收益
        if (_withUpdate) {
            massUpdatePools();
        }
        // 从startBlock开始质押挖矿，如果当前去看在startBlock之前，说明挖矿还没开始，那么上一次结算收益的区块就是startBlock，如果已经开始挖矿，就从当前去看开始结算收益
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        // 池子的总权重发生改变
        totalPoolWeight = totalPoolWeight + _poolWeight;

        pool.push(Pool({
            stTokenAddress: _stTokenAddress,
            poolWeight: _poolWeight,
            lastRewardBlock: lastRewardBlock,
            accMetaNodePerST: 0,
            stTokenAmount: 0,
            minDepositAmount: _minDepositAmount,
            unstakeLockedBlocks: _unstakeLockedBlocks
        }));

        emit AddPool(_stTokenAddress, _poolWeight, lastRewardBlock, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @notice Update the given pool's info (minDepositAmount and unstakeLockedBlocks). Can only be called by admin.
     */
    // 更新某池子的最小质押量和解质押等待区块数
    function updatePool(uint256 _pid, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        pool[_pid].minDepositAmount = _minDepositAmount;
        pool[_pid].unstakeLockedBlocks = _unstakeLockedBlocks;

        emit UpdatePoolInfo(_pid, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @notice Update the given pool's weight. Can only be called by admin.
     */
    function setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        require(_poolWeight > 0, "invalid pool weight");
        
        if (_withUpdate) {
            massUpdatePools();
        }

        totalPoolWeight = totalPoolWeight - pool[_pid].poolWeight + _poolWeight;
        pool[_pid].poolWeight = _poolWeight;

        emit SetPoolWeight(_pid, _poolWeight, totalPoolWeight);
    }

    // ************************************** QUERY FUNCTION **************************************

    /**
     * @notice Get the length/amount of pool
     */
    function poolLength() external view returns(uint256) {
        return pool.length;
    }

    /**
     * @notice Return reward multiplier over given _from to _to block. [_from, _to)
     *
     * @param _from    From block number (included)
     * @param _to      To block number (exluded)
     */
    // 对一个区块区间计算一下质押挖矿的收益
    function getMultiplier(uint256 _from, uint256 _to) public view returns(uint256 multiplier) {
        require(_from <= _to, "invalid block");
        if (_from < startBlock) {_from = startBlock;}
        if (_to > endBlock) {_to = endBlock;}
        require(_from <= _to, "end block must be greater than start block");
        bool success;
        (success, multiplier) = (_to - _from).tryMul(MetaNodePerBlock); // tryMul保证计算结果不溢出
        require(success, "multiplier overflow");
    }

    /**
     * @notice Get pending MetaNode amount of user in pool
     */
    // 查看最新区块下某池子里某用户还没有提现的token收益
    function pendingMetaNode(uint256 _pid, address _user) external checkPid(_pid) view returns(uint256) {
        return pendingMetaNodeByBlockNumber(_pid, _user, block.number);
    }

    /**
     * @notice Get pending MetaNode amount of user by block number in pool
     */
    // 根据传入的区块高度计算某池子里某用户还没有提现的token收益
    function pendingMetaNodeByBlockNumber(uint256 _pid, address _user, uint256 _blockNumber) public checkPid(_pid) view returns(uint256) {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_user];
        // 该池子的累计收益
        uint256 accMetaNodePerST = pool_.accMetaNodePerST;
        // 该池子的质押量
        uint256 stSupply = pool_.stTokenAmount;
        // 如果传入的区块高度在上次结算收益的区块之后，那么需要手动计算一下在当前区块高度的挖矿收益，前提是当前池子里有代币
        if (_blockNumber > pool_.lastRewardBlock && stSupply != 0) {
            uint256 multiplier = getMultiplier(pool_.lastRewardBlock, _blockNumber);
            uint256 MetaNodeForPool = multiplier * pool_.poolWeight / totalPoolWeight;
            accMetaNodePerST = accMetaNodePerST + MetaNodeForPool * (1 ether) / stSupply;
        }
        return user_.stAmount * accMetaNodePerST / (1 ether) - user_.finishedMetaNode + user_.pendingMetaNode;
    }

    /**
     * @notice Get the staking amount of user
     */
    // 查看某用户在某池子中的质押量
    function stakingBalance(uint256 _pid, address _user) external checkPid(_pid) view returns(uint256) {
        return user[_pid][_user].stAmount;
    }

    /**
     * @notice Get the withdraw amount info, including the locked unstake amount and the unlocked unstake amount
     */
    // 查看当前区块下某用户从某池子提现的质押代币，返回两个结果，一个是能够解质押的代币数量，一个是不可解质押的代币数量
    function withdrawAmount(uint256 _pid, address _user) public checkPid(_pid) view returns(uint256 requestAmount, uint256 pendingWithdrawAmount) {
        User storage user_ = user[_pid][_user];

        for (uint256 i = 0; i < user_.requests.length; i++) {
            if (user_.requests[i].unlockBlocks <= block.number) {
                pendingWithdrawAmount = pendingWithdrawAmount + user_.requests[i].amount;
            }
            requestAmount = requestAmount + user_.requests[i].amount;
        }
    }

    // ************************************** PUBLIC FUNCTION **************************************

    /**
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    // 问题，结算收益的时候没有给该合约发放挖矿收益
    function updatePool(uint256 _pid) public checkPid(_pid) {
        Pool storage pool_ = pool[_pid];

        if (block.number <= pool_.lastRewardBlock) {
            return;
        }
        // 计算出某池子从上一次结算收益的区块到当前区块的挖矿收益
        (bool success1, uint256 totalMetaNode) = getMultiplier(pool_.lastRewardBlock, block.number).tryMul(pool_.poolWeight);
        require(success1, "overflow");

        (success1, totalMetaNode) = totalMetaNode.tryDiv(totalPoolWeight);
        require(success1, "overflow");

        uint256 stSupply = pool_.stTokenAmount;
        if (stSupply > 0) {
            // 池子里必须有质押量才能结算收益，每一步计算都分开，每一步都要避免溢出
            // 挖矿收益总量乘以10^18
            (bool success2, uint256 totalMetaNode_) = totalMetaNode.tryMul(1 ether);
            require(success2, "overflow");
            // 挖矿总收益除以质押的代币数量
            (success2, totalMetaNode_) = totalMetaNode_.tryDiv(stSupply);
            require(success2, "overflow");
            // 累加到池子的总收益上
            (bool success3, uint256 accMetaNodePerST) = pool_.accMetaNodePerST.tryAdd(totalMetaNode_);
            require(success3, "overflow");
            pool_.accMetaNodePerST = accMetaNodePerST;
        }

        pool_.lastRewardBlock = block.number;
        // 问题：每结算一次都将质押收益从MetaNode部署者转到该合约
        bool success = MetaNode.transferFrom(metaNodeOwner, address(this), totalMetaNode);
        // console.log("updatePool.MetaNode.transferFrom(metaNodeOwner, address(this), totalMetaNode): ", success);
        require(success, "transfer failed");
        emit UpdatePool(_pid, pool_.lastRewardBlock, totalMetaNode);
    }

    /**
     * @notice Update reward variables for all pools. Be careful of gas spending!
     */
    // 遍历所有池子，结算质押挖矿收益
    function massUpdatePools() public {
        uint256 length = pool.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    /**
     * @notice Deposit staking ETH for MetaNode rewards
     */
    // 质押eth
    function depositETH() public whenNotPaused() payable {
        Pool storage pool_ = pool[ETH_PID];
        require(pool_.stTokenAddress == address(0x0), "invalid staking token address");

        uint256 _amount = msg.value;
        require(_amount >= pool_.minDepositAmount, "deposit amount is too small");

        _deposit(ETH_PID, _amount);
    }

    /**
     * @notice Deposit staking token for MetaNode rewards
     * Before depositing, user needs approve this contract to be able to spend or transfer their staking tokens
     *
     * @param _pid       Id of the pool to be deposited to
     * @param _amount    Amount of staking tokens to be deposited
     */
    // 质押erc20
    function deposit(uint256 _pid, uint256 _amount) public whenNotPaused() checkPid(_pid) {
        require(_pid != 0, "deposit not support ETH staking");
        Pool storage pool_ = pool[_pid];
        require(_amount > pool_.minDepositAmount, "deposit amount is too small");

        if(_amount > 0) {
            IERC20(pool_.stTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        }

        _deposit(_pid, _amount);
    }

    /**
     * @notice Unstake staking tokens
     *
     * @param _pid       Id of the pool to be withdrawn from
     * @param _amount    amount of staking tokens to be withdrawn
     */
    // 提交解质押请求
    function unstake(uint256 _pid, uint256 _amount) public whenNotPaused() checkPid(_pid) whenNotWithdrawPaused() {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        require(user_.stAmount >= _amount, "Not enough staking token balance");
        // 更新池子收益，将从质押开始到当前区块该池子产生的挖矿收益结算到user的信息中
        updatePool(_pid);
        // 计算能提现的收益，即截至目前该池子的所有收益-已经结算过的收益
        uint256 pendingMetaNode_ = user_.stAmount * pool_.accMetaNodePerST / (1 ether) - user_.finishedMetaNode;

        if(pendingMetaNode_ > 0) {
            user_.pendingMetaNode = user_.pendingMetaNode + pendingMetaNode_;
        }
        if(_amount > 0) {
            user_.stAmount = user_.stAmount - _amount;
            // 给用户的解质押请求内插入一个新请求
            user_.requests.push(UnstakeRequest({
                amount: _amount,
                unlockBlocks: block.number + pool_.unstakeLockedBlocks
            }));
        }
        // 质押量更新
        pool_.stTokenAmount = pool_.stTokenAmount - _amount;
        // 以当前质押量结算收益
        user_.finishedMetaNode = user_.stAmount * pool_.accMetaNodePerST / (1 ether);

        emit RequestUnstake(msg.sender, _pid, _amount);
    }

    /**
     * @notice Withdraw the unlock unstake amount
     *
     * @param _pid       Id of the pool to be withdrawn from
     */
    // 提现某池子的质押代币
    function withdraw(uint256 _pid) public whenNotPaused() checkPid(_pid) whenNotWithdrawPaused() {
        Pool storage pool_ = pool[_pid];
        //user_的requests中存了该用户所有解质押请求
        User storage user_ = user[_pid][msg.sender];

        uint256 pendingWithdraw_;
        uint256 popNum_;
        // 遍历解质押请求，计算出所有解质押请求中的可解压的代币总和
        for (uint256 i = 0; i < user_.requests.length; i++) {
            // 该遍历到request的解质押请求中的unlockBlocks大于当前区块时，就停止
            // 即只有unlockBlocks小于当前区块才能解压
            if (user_.requests[i].unlockBlocks > block.number) {
                break;
            }
            pendingWithdraw_ = pendingWithdraw_ + user_.requests[i].amount;
            popNum_++;
        }
        
        // 根据上边已经遍历过的解质押请求，将还没到解锁区块的解质押请求往前挪
        for (uint256 i = 0; i < user_.requests.length - popNum_; i++) {
            user_.requests[i] = user_.requests[i + popNum_];
        }

        // 比如有20个解质押请求，前11个是可以解压的，后9个没到区块不能解压，那么popNum_就是11，然后这里就把11~19下标的request挪到了0~8，从下标9开始，就是没有用的request了
        // 循环11次，把requests后边的11个请求弹出，这时requests中只剩下9个解质押请求
        for (uint256 i = 0; i < popNum_; i++) {
            user_.requests.pop();
        }

        if (pendingWithdraw_ > 0) {
            if (pool_.stTokenAddress == address(0x0)) {
                _safeETHTransfer(msg.sender, pendingWithdraw_);
            } else {
                IERC20(pool_.stTokenAddress).safeTransfer(msg.sender, pendingWithdraw_);
            }
        }

        emit Withdraw(msg.sender, _pid, pendingWithdraw_, block.number);
    }

    /**
     * @notice Claim MetaNode tokens reward
     *
     * @param _pid       Id of the pool to be claimed from
     */
    // 提现质押挖矿收益
    function claim(uint256 _pid) public whenNotPaused() checkPid(_pid) whenNotClaimPaused() {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];
        // 更新池子收益
        updatePool(_pid);
        // 计算总的待提现奖励 user_.stAmount * pool_.accMetaNodePerST / (1 ether) - user_.finishedMetaNode 是从上次结算后到现在的奖励，user_.pendingMetaNode上次算出来的待提现奖励
        // 问题：提现挖矿收益时为什么不是只能提现解质押请求中那部分质押代币产生的挖矿收益，这里体现的挖矿收益应该是从质押开始到现在总的挖矿收益
        uint256 pendingMetaNode_ = user_.stAmount * pool_.accMetaNodePerST / (1 ether) - user_.finishedMetaNode + user_.pendingMetaNode;
        if(pendingMetaNode_ > 0) {
            user_.pendingMetaNode = 0; //防止重放攻击
            _safeMetaNodeTransfer(msg.sender, pendingMetaNode_);
        }
        // 重新计算已结算奖励
        user_.finishedMetaNode = user_.stAmount * pool_.accMetaNodePerST / (1 ether);

        emit Claim(msg.sender, _pid, pendingMetaNode_);
    }

    // ************************************** INTERNAL FUNCTION **************************************

    /**
     * @notice Deposit staking token for MetaNode rewards
     *
     * @param _pid       Id of the pool to be deposited to
     * @param _amount    Amount of staking tokens to be deposited
     */
    function _deposit(uint256 _pid, uint256 _amount) internal {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];
        // 用户质押时也要结算各池子的收益
        updatePool(_pid);

        if (user_.stAmount > 0) {
            // 用户之前已经质押过，那就先算一下未提现的token奖励
            // uint256 accST = user_.stAmount.mulDiv(pool_.accMetaNodePerST, 1 ether);
            // 计算出该用户之前质押的代币的挖矿总收益
            (bool success1, uint256 accST) = user_.stAmount.tryMul(pool_.accMetaNodePerST);
            require(success1, "user stAmount mul accMetaNodePerST overflow");
            (success1, accST) = accST.tryDiv(1 ether);
            require(success1, "accST div 1 ether overflow");
            // 该用户之前的挖矿总收益减去已经完成结算的挖矿收益，就是还没结算的挖矿收益
            (bool success2, uint256 pendingMetaNode_) = accST.trySub(user_.finishedMetaNode);
            require(success2, "accST sub finishedMetaNode overflow");

            if(pendingMetaNode_ > 0) {
                (bool success3, uint256 _pendingMetaNode) = user_.pendingMetaNode.tryAdd(pendingMetaNode_);
                require(success3, "user pendingMetaNode overflow");
                user_.pendingMetaNode = _pendingMetaNode;
            }
        }
        // 上边先计算出用户之前的质押收益，然后再把这次的质押量加到用户的总质押量上
        if(_amount > 0) {
            (bool success4, uint256 stAmount) = user_.stAmount.tryAdd(_amount);
            require(success4, "user stAmount overflow");
            user_.stAmount = stAmount;
        }
        // 池子的质押量增加
        (bool success5, uint256 stTokenAmount) = pool_.stTokenAmount.tryAdd(_amount);
        require(success5, "pool stTokenAmount overflow");
        pool_.stTokenAmount = stTokenAmount;

        // user_.finishedMetaNode = user_.stAmount.mulDiv(pool_.accMetaNodePerST, 1 ether);
        // 根据用户当前的总质押量计算出截止现在总共多少收益
        (bool success6, uint256 finishedMetaNode) = user_.stAmount.tryMul(pool_.accMetaNodePerST);
        require(success6, "user stAmount mul accMetaNodePerST overflow");

        (success6, finishedMetaNode) = finishedMetaNode.tryDiv(1 ether);
        require(success6, "finishedMetaNode div 1 ether overflow");
        // 修改用户已结算收益
        user_.finishedMetaNode = finishedMetaNode;

        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * @notice Safe MetaNode transfer function, just in case if rounding error causes pool to not have enough MetaNodes
     *
     * @param _to        Address to get transferred MetaNodes
     * @param _amount    Amount of MetaNode to be transferred
     */
    function _safeMetaNodeTransfer(address _to, uint256 _amount) internal {
        uint256 MetaNodeBal = MetaNode.balanceOf(address(this));
        // console.log("_amount: ", _amount/1e18);
        // console.log("MetaNodeBal: ", MetaNodeBal/1e18);
        if (_amount > MetaNodeBal) {
            bool success = MetaNode.transfer(_to, MetaNodeBal);
            // console.log("MetaNode.transfer(_to, MetaNodeBal): ", success);
            require(success, "transfer failed");
        } else {
            bool success = MetaNode.transfer(_to, _amount);
            // console.log("MetaNode.transfer(_to, _amount): ", success);
            require(success, "transfer failed");
        }
    }

    /**
     * @notice Safe ETH transfer function
     *
     * @param _to        Address to get transferred ETH
     * @param _amount    Amount of ETH to be transferred
     */
    function _safeETHTransfer(address _to, uint256 _amount) internal {
        (bool success, bytes memory data) = address(_to).call{
            value: _amount
        }("");

        require(success, "ETH transfer call failed");
        if (data.length > 0) {
            require(
                abi.decode(data, (bool)),
                "ETH transfer operation did not succeed"
            );
        }
    }
}