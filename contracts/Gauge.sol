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

// TODO, both primary rewards and extra rewards are contingent upon [boost factor (derivedBalance), user balance in gauge] but otherwise share no logic.
// They do not share the way reward rate is calculated.  Reward rate for Axial is based on a weekly cadence.  Extra rewards are determined by:
// rewardPerSec[token]
// If we run out of tokens we need to handle it gracefully!!!!!!!!!
// TEST FOR RUNNING OUT OF TOKENS, MAKE SURE IT DOESNT CONTINUE TRYING TO DISTRIBUTE THE AUTHORITY TO WITHDRAW ADDITIONAL TOKENS
// reward tokens should only be "put" into claimable pool if there is in fact a balance.

contract Gauge is ProtocolGovernance, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // ==================== External Dependencies ==================== //

    /// @notice the Axial token contract
    IERC20 public constant AXIAL =
        IERC20(0xcF8419A615c57511807236751c0AF38Db4ba3351);

    /// @notice token to allow boosting rewards - VEAXIAL
    AccruingStake public immutable VEAXIAL;

    /// @notice token to be staked in return for rewards
    IERC20 public immutable poolToken;

    // ==================== Events ==================== //

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward, address token);
    event RewardAdded(uint256 reward, address token);

    // ==================== State Variables ==================== //

    /// @dev tokens to be distributed as a reward to stakers
    address[] public rewardTokens;
    /// @dev contract responsible for distributing rewards (should be Gauge Proxy)
    address public gaugeProxy;
    uint256 public constant DURATION = 7 days;

    uint256 public periodFinish = 0;

    /// @dev token => rate
    mapping(address => uint256) public rewardRates;
    mapping(address => uint256) public rewardPerTokenStored;
    /// @dev token => partner
    mapping(address => address) public tokenPartners;

    uint256 public lastUpdateTime;

    /// @dev user => token => amount
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;
    /// @dev user => token => amount
    mapping(address => mapping(address => uint256)) public rewards;

    uint256 private _totalSupply;
    uint256 public derivedSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) public derivedBalances;

    // ==================== Modifiers ==================== //

    modifier updateReward(address account) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            rewardPerTokenStored[rewardTokens[i]] = rewardPerToken(i);
            lastUpdateTime = lastTimeRewardApplicable();
            if (account != address(0)) {
                rewards[account][rewardTokens[i]] = earned(account, i);
                userRewardPerTokenPaid[account][
                    rewardTokens[i]
                ] = rewardPerTokenStored[rewardTokens[i]];
            }
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
        // adding a new reward token to the array
        rewardTokens.push(tokenAddress);
        rewardRates[tokenAddress] = 0;
        tokenPartners[tokenAddress] = partnerAddress;
    }

    /// @notice returns the amount of reward tokens for the gauge
    function getNumRewardTokens() public view returns (uint256) {
        return rewardTokens.length;
    }

    /// @notice return how many of our reward tokens is the user receiving per lp token
    /// @dev (e.g. how many teddy or axial is received per AC4D token)
    function rewardPerToken(uint256 tokenIndex) public view returns (uint256) {
        if (_totalSupply == 0) { // todo, does this need to be made per token?
            return rewardPerTokenStored[rewardTokens[tokenIndex]];
        }

        address token = rewardTokens[tokenIndex];

        //if (tokenIndex == 2) {
        //     console.log(rewardTokens[tokenIndex]);
        //     console.log("rPTS=", rewardPerTokenStored[rewardTokens[tokenIndex]]);
        //     console.log("lTRA=", lastTimeRewardApplicable(token));
        //     console.log("lUT=", lastUpdateTime[token]);
        //     console.log("rR=", rewardRates[token]);
        //     console.log("/dS=", derivedSupply);
        //     console.log("...=", rewardPerTokenStored[token].add(lastTimeRewardApplicable(token).sub(lastUpdateTime[token]).mul(rewardRates[token]).mul(1e18).div(derivedSupply)));
        // //}
        // rPTS + (lTRA - lUT * rR * 1e18 / dS)

        // TODO: does derivedSupply also need to be made per token?

        return rewardPerTokenStored[rewardTokens[tokenIndex]].add(lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRates[token]).mul(1e18).div(derivedSupply));
    }

    /// @notice getting the reward to be received for each reward's respective staking period
    function getRewardForDuration(uint256 tokenIndex)
        external
        view
        returns (uint256)
    {
        return rewardRates[rewardTokens[tokenIndex]].mul(DURATION);
    }

    /// @notice gets the amount of reward tokens that the user has earned
    function earned(address account, uint256 tokenIndex)
        public
        view
        returns (uint256)
    {
        // x = dB * ( rPT - uRPTP ) / 1e18 + r 
        //if (tokenIndex == 2) {
            // console.log(rewardTokens[tokenIndex]);
            // console.log("dB=", derivedBalances[account]);
            // console.log("rPT=", rewardPerToken(tokenIndex));
            // console.log("uRPTP=", userRewardPerTokenPaid[account][rewardTokens[tokenIndex]]);
            // console.log("r=", rewards[account][rewardTokens[tokenIndex]]);
        //}
        return derivedBalances[account].mul(rewardPerToken(tokenIndex).sub(userRewardPerTokenPaid[account][rewardTokens[tokenIndex]])).div(1e18).add(rewards[account][rewardTokens[tokenIndex]]);
    }

    /// @notice This function is to allow us to update the gaugeProxy without resetting the old gauges.
    /// @dev this changes where it is receiving the axial tokens, as well as changes the governance
    function changeDistribution(address _distribution) external onlyGovernance {
        gaugeProxy = _distribution;
    }

    /// @notice total supply of our lp tokens in the gauge (e.g. AC4D tokens present)
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice balance of lp tokens that user has in the gauge (e.g. amount of AC4D a user has)
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    /// @notice returns boost factor for specified account
    /// THIS IS THE USERS BOOST, DO NOT BE CONFUSED BY THE NAME
    /// TODO CHANGE THE NAME OF THIS TO SOMETHING WHICH DESCRIBES WHAT IT IS THERE FOR
    function derivedBalance(address account) public view returns (uint256) {
        uint256 _userBalanceInGauge = _balances[account];

        // If the user has no tokens in the gauge, return 0
        if (_userBalanceInGauge == 0) {
            return 0;
        }

        uint256 usersVeAxialBalance = VEAXIAL.getAccrued(account); // get the veAxial balance of the account
        uint256 totalVeAxial = VEAXIAL.getTotalAccrued(); // get the total veAxial

        uint256 _adjusted;
        if (totalVeAxial != 0) {
            _adjusted = (_totalSupply.mul(usersVeAxialBalance).div(totalVeAxial));
        }

        return (_userBalanceInGauge + _adjusted) / _userBalanceInGauge;
    }

    function kick(address account) public {
        uint256 _derivedBalance = derivedBalances[account];
        derivedSupply = derivedSupply.sub(_derivedBalance);
        _derivedBalance = derivedBalance(account);
        derivedBalances[account] = _derivedBalance;
        derivedSupply = derivedSupply.add(_derivedBalance);
    }

    /// @notice internal deposit function
    function _deposit(uint256 amount, address account)
        internal
        nonReentrant
        updateReward(account)
    {
        require(amount > 0, "Cannot stake 0");
        poolToken.safeTransferFrom(account, address(this), amount);
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
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
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice withdraws all pool tokens from the gauge
    function withdrawAll() external {
        _withdraw(_balances[msg.sender]);
    }

    /// @notice withdraw specified amount of tokens from the message senders balance
    function withdraw(uint256 amount) external {
        _withdraw(amount);
    }

    /// @notice get reward tokens from gauge
    function getReward(uint256 tokenIndex)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        uint256 reward = rewards[msg.sender][rewardTokens[tokenIndex]];
        if (reward > 0) {
            IERC20(rewardTokens[tokenIndex]).safeTransfer(msg.sender, reward);
            rewards[msg.sender][rewardTokens[tokenIndex]] = 0;
            emit RewardPaid(msg.sender, reward, rewardTokens[tokenIndex]);
        }
    }

    /// @notice claims specific reward indices
    function claimRewards(uint256[] calldata tokenIndices) public {
        for (uint256 i = 0; i < tokenIndices.length; ++i) {
            getReward(tokenIndices[i]);
        }
    }

    /// @notice claims all rewards
    function claimAllRewards() public {
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            getReward(i);
        }
    }

    /// @notice withdraw deposited pool tokens and claim reward tokens
    function exit() external {
        _withdraw(_balances[msg.sender]);
        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            getReward(i);
        }
    }

    // TODO: Chesterton's fence, see if this function is being used anywhere
    function notifyReward(uint256 reward, address tokenAddress)
        external
        updateReward(address(0))
    {
        address userAddr = msg.sender;
        require (tokenPartners[tokenAddress] == userAddr, "You do not have the right");
        IERC20(tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            reward
        );
        if (block.timestamp >= periodFinish) {
            rewardRates[tokenAddress] = reward.div(DURATION);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(
                rewardRates[tokenAddress]
            );
            rewardRates[tokenAddress] = reward.add(leftover).div(
                DURATION
            );
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = IERC20(tokenAddress).balanceOf(
            address(this)
        );
        // console.log("balance=", balance);
        // console.log("rewardRate=", rewardRates[tokenAddress]);
        // console.log("balance/duration=", balance.div(DURATION));
        require(
            rewardRates[tokenAddress] <= balance.div(DURATION),
            "Provided reward too high for reward token"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(DURATION);
        emit RewardAdded(reward, tokenAddress);
    }

    /// @notice only called by the GaugeProxy and so only deals in the native token
    function notifyRewardAmount(uint256 reward)
        external
        onlyDistribution
        updateReward(address(0))
    {
        IERC20(rewardTokens[0]).safeTransferFrom(
            gaugeProxy,
            address(this),
            reward
        );
        if (block.timestamp >= periodFinish) {
            rewardRates[rewardTokens[0]] = reward.div(DURATION);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRates[rewardTokens[0]]);
            rewardRates[rewardTokens[0]] = reward.add(leftover).div(DURATION);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = IERC20(rewardTokens[0]).balanceOf(address(this));
        require(
            rewardRates[rewardTokens[0]] <= balance.div(DURATION),
            "Provided reward too high"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(DURATION);
        emit RewardAdded(reward, rewardTokens[0]);
    }
}
