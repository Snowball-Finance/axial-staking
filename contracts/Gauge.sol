/// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {ProtocolGovernance} from "./libraries/ProtocolGovernance.sol";
import {AccruingStake} from "./AccruingStake.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "hardhat/console.sol";

// TODO, both primary rewards and extra rewards are contingent upon [boost factor (boostFactor), user balance in gauge] but otherwise share no logic.
// They do not share the way reward rate is calculated.  Reward rate for Axial is based on a weekly cadence.  Extra rewards are determined by:
// rewardPerSec[token]
// If we run out of tokens we need to handle it gracefully!!!!!!!!!
// TEST FOR RUNNING OUT OF TOKENS, MAKE SURE IT DOESNT CONTINUE TRYING TO DISTRIBUTE THE AUTHORITY TO WITHDRAW ADDITIONAL TOKENS
// reward tokens should only be "put" into claimable pool if there is in fact a balance.

contract Gauge is ProtocolGovernance, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // ==================== External Dependencies ==================== //

    /// The Axial token contract
    IERC20 public constant AXIAL = IERC20(0xcF8419A615c57511807236751c0AF38Db4ba3351);

    /// Token to allow boosting partner token rewards - VEAXIAL
    AccruingStake public immutable VEAXIAL;

    /// Token to be staked in return for primary rewards
    IERC20 public immutable poolToken;

    // ==================== Events ==================== //

    /// @notice emitted when a user stakes
    /// @param user The address of the user who staked
    /// @param amount the quantity of tokens the user staked
    event Staked(address indexed user, uint256 amount);

    /// @notice emitted when a user withdraws
    /// @param user The address of the user who withdrew
    /// @param amount The quantity of tokens the user withdrew
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice emitted when a reward is claimed by a user
    /// @param user The address of the user who claimed the reward
    /// @param reward The quantity of tokens the user claimed
    /// @param token The address of the token the user claimed
    event RewardPaid(address indexed user, uint256 reward, address token);

    /// @notice emitted when the primary reward or partner rewards are added to the gauge
    /// @param reward the quantity of tokens added
    /// @param token the address of the reward token
    event RewardAdded(uint256 reward, address token);

    // ==================== State Variables ==================== //

    /// tokens to be distributed as a reward to stakers, 0 is primary reward and 1-... are partner rewards
    address[] public rewardTokens;

    /// contract responsible for distributing primary rewards (should be Gauge Proxy)
    address public gaugeProxy;

    /// Distribution interval for primary reward token
    uint256 public constant PRIMARY_REWARD_DURATION = 7 days;
    mapping(address => uint256) partnerRewardDurations;

    /// Used to keep track of reward token intervals
    // token => time
    mapping (address => uint256) public periodFinish;
    mapping (address => uint256) public lastUpdateTime;

    /// Primary reward token rate
    mapping (address => uint256) public rewardRates;

    // token => amount
    mapping (address => uint256) public rewardPerTokenStored;

    /// @dev user => reward token => amount
    mapping(address => mapping (address => uint256)) public userRewardPerTokenPaid;

    /// @dev user => reward token => amount
    mapping(address => mapping (address => uint256)) public rewards;

    /// total supply of the primary reward token and partner reward tokens
    uint256 private _totalLPTokenSupply;

    /// boost-adjusted supply of the reward tokens
    mapping (address => uint256) public derivedSupply;

    /// user => LP token balance
    mapping(address => uint256) private _lpTokenBalances;

    /// user => boost factor
    mapping(address => uint256) public boostFactors;

    /// PARTNER STUFF:

    /// partner reward token => partner, used to determine permission for setting reward rates
    mapping(address => address) public tokenPartners;

    // ==================== Modifiers ==================== //

    // Affects all rewards
    modifier updateReward(address account) {
        for (uint i = 0; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            //lastUpdateTime[token] = lastTimeRewardApplicable(token);
            rewardPerTokenStored[token] = rewardPerToken(token);
            if (account != address(0)) {
                rewards[account][token] = earned(account, token);
                userRewardPerTokenPaid[account][token] = rewardPerTokenStored[token];
            }
            lastUpdateTime[token] = lastTimeRewardApplicable(token);
        }
        _;
        if (account != address(0)) {
            kick(account);
        }
    }

    modifier onlyDistribution() {
        require(msg.sender == gaugeProxy, "Gauge: not distribution contract");
        _;
    }

    modifier validAddress(address _rewardToken) {
        require(Address.isContract(_rewardToken), "Gauge: not a contract");
        _;
    }

    constructor(
        address _token,
        address _governance,
        address _veaxial
    ) {
        poolToken = IERC20(_token);
        gaugeProxy = msg.sender;
        governance = _governance;
        VEAXIAL = AccruingStake(_veaxial);
        rewardTokens.push(address(AXIAL));
    }

    // ==================== Reward Token Logic ==================== //

    /// @notice adding a reward token to our array
    /// @param tokenAddress Reward token to be added to our rewardTokens array
    /// @param partnerAddress Address of partner who has permission to set the token reward rate
    function addRewardToken(address tokenAddress, address partnerAddress)
        public
        onlyGovernance
        validAddress(tokenAddress)
    {
        require(tokenPartners[tokenAddress] == address(0), "Token already in use");
        tokenPartners[tokenAddress] = partnerAddress; // certify partner with the authority to provide rewards for the token
        rewardTokens.push(tokenAddress); // add token to our list of reward token addresses
    }

    /// @notice returns the amount of reward tokens for the gauge
    function getNumRewardTokens() public view returns (uint256) {
        return rewardTokens.length;
    }

    function partnerDepositRewardTokens(address tokenAddress, uint256 amount, uint256 rewardPerSec) external updateReward(address(0)) {
        require(tokenPartners[tokenAddress] == msg.sender, "You do not have the right.");
        require (rewardPerSec != 0, "Cannot set reward rate to 0");
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);

        // Get balance in case there was some pending balance
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));

        uint duration = balance / rewardPerSec;

        lastUpdateTime[tokenAddress] = block.timestamp;
        periodFinish[tokenAddress] = block.timestamp.add(duration);
        rewardRates[tokenAddress] = rewardPerSec; // Just set the reward rate even if there is still pending balance
        emit RewardAdded(amount, tokenAddress);
    }

    /// @notice return how many of our reward tokens is the user receiving per lp token
    /// @dev (e.g. how many teddy or axial is received per AC4D token)
    function rewardPerToken(address token) public view returns (uint256) {
        if (_totalLPTokenSupply == 0 || derivedSupply[token] == 0) {
            console.log(derivedSupply[token]);
            return rewardPerTokenStored[token];
        }

        // rPTS + (lTRA - lUT * rR * 1e18 / dS)
        // console.log("rPTS=", rewardPerTokenStored[token]);
        // console.log("lTRA=", lastTimeRewardApplicable(token));
        // console.log("lUT=", lastUpdateTime[token]);
        // console.log("rR1e18=", rewardRates[token] * 1e18);
        // console.log("dS=", derivedSupply[token]);

        // Debug
        // uint256 rPT = rewardPerTokenStored[token].add(lastTimeRewardApplicable(token).sub(lastUpdateTime[token]).mul(rewardRates[token]).mul(1e18).div(derivedSupply[token]));
        // console.log("rPT=", rPT);
        uint256 r = lastTimeRewardApplicable(token).sub(lastUpdateTime[token]).mul(rewardRates[token]).mul(1e18);
        console.log("r=", r);
        uint256 ds = derivedSupply[token];
        console.log("ds=", ds);

        return rewardPerTokenStored[token].add(lastTimeRewardApplicable(token).sub(lastUpdateTime[token]).mul(rewardRates[token]).mul(1e18).div(derivedSupply[token]));
    }

    /// @notice getting the reward to be received for primary tokens respective staking period
    function getRewardForDuration() external view returns (uint256)
    {
        address token = rewardTokens[0];
        return rewardRates[token].mul(PRIMARY_REWARD_DURATION);
    }

    /// @notice gets the amount of reward tokens that the user has earned
    function earned(address account, address token)
        public
        view
        returns (uint256)
    {
        // x = bF * ( rPT - uRPTP ) / 1e18 + r 
        // console.log("bF=", boostFactors[account]);
        // console.log("rPT=", rewardPerToken(token));
        // console.log("uRPTP=", userRewardPerTokenPaid[account][token]);
        // console.log("1e18+r=", 1e18 + rewards[account][token]);

        // debug
        // uint256 e = boostFactors[account].mul(rewardPerToken(token).sub(userRewardPerTokenPaid[account][token])).div(1e18).add(rewards[account][token]);
        // console.log("e=", e);

        uint256 uRPTP = userRewardPerTokenPaid[account][token];
        console.log("uRPTP=", uRPTP);

        return userShare(account).mul(boostFactors[account].mul(rewardPerToken(token).sub(userRewardPerTokenPaid[account][token])).div(1e18).add(rewards[account][token])).div(1e18);

        //return boostFactors[account].mul(rewardPerToken(token).sub(userRewardPerTokenPaid[account][token])).div(1e18).add(rewards[account][token]);
    }

    /// @notice This function is to allow us to update the gaugeProxy without resetting the old gauges.
    /// @dev this changes where it is receiving the axial tokens, as well as changes the governance
    function changeDistribution(address _distribution) external onlyGovernance {
        gaugeProxy = _distribution;
    }

    /// @notice total supply of our lp tokens in the gauge (e.g. AC4D tokens present)
    function totalSupply() external view returns (uint256) {
        return _totalLPTokenSupply;
    }

    /// @notice balance of lp tokens that user has in the gauge (e.g. amount of AC4D a user has)
    function balanceOf(address account) external view returns (uint256) {
        return _lpTokenBalances[account];
    }

    function lastTimeRewardApplicable(address token) public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish[token]);
    }

    // returns the users share of the total LP supply * 1e18
    function userShare(address account) public view returns (uint256) {
        return _lpTokenBalances[account] * 1e18 / _totalLPTokenSupply;
    }

    /// @notice returns boost factor for specified account
    function boostFactor(address account) public view returns (uint256) {
        uint256 _userBalanceInGauge = _lpTokenBalances[account];

        // If the user has no tokens in the gauge, return 0 
        if (_userBalanceInGauge == 0) {
            return 0;
        }

        uint256 usersVeAxialBalance = VEAXIAL.getAccrued(account); // get the veAxial balance of the account
        uint256 totalVeAxial = VEAXIAL.getTotalAccrued(); // get the total veAxial

        uint256 _adjusted;
        if (totalVeAxial != 0) {
            _adjusted = (_totalLPTokenSupply.mul(usersVeAxialBalance).div(totalVeAxial));
        }

        return (_userBalanceInGauge + _adjusted) / _userBalanceInGauge;
    }

    function kick(address account) public {
        uint256 _boostFactor = boostFactors[account];

        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            //console.log(token);
            //console.log("account=", account);
            //console.log("derivedSupply=", derivedSupply[token]);
            //console.log("boostFactor=", _boostFactor);
            if (derivedSupply[token] > 0) {
                derivedSupply[token] = derivedSupply[token].sub(_boostFactor);
            }
        }

        _boostFactor = boostFactor(account);
        boostFactors[account] = _boostFactor;

        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            //console.log(token);
            derivedSupply[token] = derivedSupply[token].add(_boostFactor);
        }
    }

    /// @notice internal deposit function
    function _deposit(uint256 amount, address account)
        internal
        nonReentrant
        updateReward(account)
    {
        require(amount > 0, "Cannot stake 0");
        poolToken.safeTransferFrom(account, address(this), amount);
        _totalLPTokenSupply = _totalLPTokenSupply.add(amount);
        _lpTokenBalances[account] = _lpTokenBalances[account].add(amount);
        emit Staked(account, amount);
    }

    /// @notice deposits all pool tokens to the gauge
    function depositAll() external {
        _deposit(poolToken.balanceOf(msg.sender), msg.sender);
    }

    /// @notice deposits specified amount of tokens into the gauge from msg.sender
    function deposit(uint256 amount) external {
        _deposit(amount, msg.sender);
    }

    /// @notice deposit specified amount of tokens into the gauge on behalf of specified account
    /// @param amount amount of tokens to be deposited
    /// @param account account to deposit from
    function depositFor(uint256 amount, address account) external {
        require(account != address(this), "!account"); // prevent inflation
        _deposit(amount, account);
    }

    /// @notice internal withdraw function
    function _withdraw(uint256 amount)
        internal
        nonReentrant
        updateReward(msg.sender)
    {
        poolToken.safeTransfer(msg.sender, amount);
        require(amount > 0, "Cannot withdraw 0");
        _totalLPTokenSupply = _totalLPTokenSupply.sub(amount);
        _lpTokenBalances[msg.sender] = _lpTokenBalances[msg.sender].sub(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice withdraws all pool tokens from the gauge
    function withdrawAll() external {
        _withdraw(_lpTokenBalances[msg.sender]);
    }

    /// @notice withdraw specified amount of primary pool tokens from the message senders balance
    function withdraw(uint256 amount) external {
        _withdraw(amount);
    }

    /// @notice get reward tokens from gauge
    function getReward(uint256 tokenIndex)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        address token = rewardTokens[tokenIndex];
        require(token != address(0), "Reward token does not exist");
        uint256 reward = rewards[msg.sender][token];
        console.log("reward=", reward);
        // DEBUG
        uint256 _reward = IERC20(token).balanceOf(address(this));
        console.log("balance=", _reward);
        if (reward > 0) {
            IERC20(token).safeTransfer(msg.sender, reward);
            rewards[msg.sender][token] = 0;
            emit RewardPaid(msg.sender, reward, token);
        }
    }

    /// @notice claims specific reward indices
    function getRewards(uint256[] calldata tokenIndices) public {
        for (uint256 i = 0; i < tokenIndices.length; ++i) {
            getReward(tokenIndices[i]);
        }
    }

    // /// @notice claims all rewards
    function getAllRewards() public {
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            getReward(i);
        }
    }

    /// @notice withdraw deposited pool tokens and claim reward tokens
    function exit() external {
        _withdraw(_lpTokenBalances[msg.sender]);
        getAllRewards();
    }

    /// @notice only called by the GaugeProxy and so only deals in the native token
    function notifyRewardAmount(uint256 reward)
        external
        onlyDistribution
        updateReward(address(0))
    {
        address token = rewardTokens[0];
        IERC20(token).safeTransferFrom(
            gaugeProxy,
            address(this),
            reward
        );
        if (block.timestamp >= periodFinish[token]) {
            rewardRates[token] = reward.div(PRIMARY_REWARD_DURATION);
        } else {
            uint256 remaining = periodFinish[token].sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRates[token]);
            //console.log(PRIMARY_REWARD_DURATION);
            rewardRates[token] = reward.add(leftover).div(PRIMARY_REWARD_DURATION);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(
            rewardRates[token] <= balance.div(PRIMARY_REWARD_DURATION),
            "Provided reward too high"
        );

        lastUpdateTime[token] = block.timestamp;
        periodFinish[token] = block.timestamp.add(PRIMARY_REWARD_DURATION);
        emit RewardAdded(reward, token);
    }
}
