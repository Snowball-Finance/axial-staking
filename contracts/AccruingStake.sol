// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @title A staking contract which accrues over time based on the amount staked
/// @author Auroter
/// @notice Allows you to lock tokens in exchange for distribution tokens
/// @notice Locks can be deposited into or closed
/// @dev Simply call stake(...) to deposit tokens
/// @dev Call getAccrued(user) / getTotalAccrued() = users share

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";

contract AccruingStake is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Info pertaining to staking contract
    address public StakedToken; // An ERC20 Token to be staked (i.e. Axial)
    string public Name; // New asset after staking (i.e. veAxial)
    string public Symbol; // New asset symbol after staking (i.e. veAXIAL)
    //uint256 private AprDenominator = 1 days;  // Timeframe it takes for the user to accrue X tokens

    // Info pertaining to users
    uint256 private TotalTokensLocked; // Total balance of tokens users have locked
    uint256 private TotalTockensAccrued; // Total balance of accrued tokens currently awarded to users
    uint256 private LastUserIndexUpdated; // Index of the user whose accrual was most recently updated
    uint256 private TimeStamp; // Last time Total Accrual was updated
    address[] private Users; // An array containing all user addresses
    mapping(address => AccrueVe) private Locks; // A mapping of each users tokens staked

    struct AccrueVe {
        uint256 AccruedTokens; // Quantity of tokens awarded to the user at time of Timestamp
        uint256 StakedTokens; // Quantity of tokens the user has staked
        uint256 TimeStamp; // Last time the accrual was updated
        uint256 UserIndex; // Index of user, used to manage iteration
        bool Initialized; // True if the user is staked
    }

    /// @notice Constructor
    /// @param _stakedToken Address of the token our users will deposit and lock in exchange for governance tokens
    /// @param _name Desired name of our governance token
    /// @param _symbol Desired symbol of our governance token
    /// @param _governance Address of wallet which will be given adminstrative access to this contract
    constructor(
        address _stakedToken,
        string memory _name,
        string memory _symbol,
        address _governance
    ) {
        transferOwnership(_governance);
        StakedToken = _stakedToken;
        Name = _name;
        Symbol = _symbol;
    }

    /// @notice Emitted when a user creates a new stake
    /// @param user Address of the user who staked
    /// @param amount Quantity of tokens deposited
    event userStaked(address indexed user, uint256 amount);

    /// @notice Emitted when a user adds to their stake
    /// @param user Address of the user who staked
    /// @param amount Quantity of tokens deposited
    event userRestaked(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws their funds
    /// @param user Address of the user who withdrew
    /// @param amount Quantity of tokens withdrawn
    /// @param accrued Quantity of accrued tokens lost
    event userWithdrew(address indexed user, uint256 amount, uint256 accrued);

    /// @notice Get the number of tokens a user currently has staked
    /// @param _userAddr Address of any user to view the number of vested tokens they have not yet claimed
    /// @return Quantity of tokens which a user currently has staked
    function getStaked(address _userAddr) public view returns (uint256) {
        return Locks[_userAddr].StakedTokens;
    }

    /// @notice Get the total number of tokens a user has accrued
    /// @param _userAddr Address of any user to view the number of vested tokens they have not yet claimed
    /// @return Quantity of tokens which a user has accrued over time
    /// @dev Use this function to get the numerator for a users share of the rewards pool
    function getAccrued(address _userAddr) public view returns (uint256) {
        //return Locks[_userAddr].AccruedTokens;
        return Locks[_userAddr].AccruedTokens + (Locks[_userAddr].StakedTokens * (block.timestamp - Locks[_userAddr].TimeStamp));
    }

    /// @notice Get the total number of tokens accrued via this contract
    /// @return Quantity of all tokens awarded by this contract
    /// @dev Use this function to get the denominator for a users share of the rewards pool
    function getTotalAccrued() public view returns (uint256) {
        //return TotalTockensAccrued;
        return TotalTockensAccrued + (TotalTokensLocked * (block.timestamp - TimeStamp));
    }

    /// @notice Retrieve a list of all users who have ever staked
    /// @return An array of addresses of all users who have ever staked
    function getAllUsers() public view returns (address[] memory) {
        return Users;
    }

    // Accrual is tokens locked * seconds
    /// @notice Update the accrual for a specific user
    /// @param _userAddr address of user to update
    /// @dev This synchronizes a users accrual when their deposit amount changes
    function _updateUsersAccrual(address _userAddr) private {
        AccrueVe storage lock = Locks[_userAddr];
        uint256 blockTimestamp = block.timestamp;

        uint256 accrual = (blockTimestamp - lock.TimeStamp) * lock.StakedTokens;
        //TotalTockensAccrued += accrual;

        lock.TimeStamp = blockTimestamp;
        lock.AccruedTokens += accrual;
    }

    /// @notice Update the total accrual for all users
    /// @dev This updates the value used as the denominator for a users accrual share
    /// @dev This must always be called before changing the amount of tokens deposited in this contract
    function _updateTotalAccrual() private {
        uint256 currentTime = block.timestamp;
        uint256 delta = currentTime - TimeStamp;
        TotalTockensAccrued += TotalTokensLocked * delta;
        TimeStamp = currentTime;
    }

        /// @notice Allow owner to reclaim tokens not matching the deposit token
    /// @notice Some users may have accidentally sent these to the contract
    /// @param _token Address of the non-deposit token
    function ownerRemoveNonDepositToken(address _token) public nonReentrant onlyOwner {
        require(_token != StakedToken, "!invalid");
        uint256 balanceOfToken = IERC20(_token).balanceOf(address(this));
        require(balanceOfToken > 0, "!balance");
        IERC20(_token).safeTransfer(owner(), balanceOfToken);
    }

    /// @notice Transfers deposited tokens back to their original owner
    /// @notice This will reset the users accrual!
    /// @dev This could be called by the web application via a button or some other means
    function withdrawMyFunds() external nonReentrant {
        address userAddr = msg.sender;
        uint256 fundsToClaim = Locks[userAddr].StakedTokens;

        require(fundsToClaim > 0, "!funds");
        IERC20(StakedToken).safeTransfer(userAddr, fundsToClaim);

        // decrement totals
        _updateTotalAccrual();
        TotalTokensLocked -= fundsToClaim;
        TotalTockensAccrued -= Locks[userAddr].AccruedTokens;

        // Broadcast withdrawal
        emit userWithdrew(userAddr, fundsToClaim, Locks[userAddr].AccruedTokens);

        Locks[userAddr].StakedTokens = 0;
        Locks[userAddr].AccruedTokens = 0;
        //Locks[userAddr].TimeStamp = 0;
        Locks[userAddr].Initialized = false;

        // Fairly efficient way of removing user from list
        uint256 lastUsersIndex = Users.length - 1;
        uint256 myIndex = Locks[userAddr].UserIndex;
        Locks[Users[lastUsersIndex]].UserIndex = myIndex;
        Users[myIndex] = Users[lastUsersIndex];
        Users.pop();
    }

    /// @notice Deposit tokens into the contract, adjusting accrual rate
    /// @param _amount Number of tokens to deposit
    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "!amount");

        address userAddr = msg.sender;

        // Receive the users tokens
        require(IERC20(StakedToken).balanceOf(userAddr) >= _amount, "!balance");
        IERC20(StakedToken).safeTransferFrom(userAddr,  address(this), _amount);

        _updateTotalAccrual();
        TotalTokensLocked += _amount;

        // Keep track of new users
        if (!Locks[userAddr].Initialized) {
            Users.push(userAddr);
            Locks[userAddr].Initialized = true;
            Locks[userAddr].TimeStamp = block.timestamp; // begin accrual from time of initial deposit
            Locks[userAddr].UserIndex = Users.length - 1;
            emit userStaked(userAddr, _amount);
        } else {
            _updateUsersAccrual(userAddr); // balance ledger before accrual rate is increased
            emit userRestaked(userAddr, _amount);
        }

        // Update balance
        Locks[userAddr].StakedTokens += _amount;
    }
}
