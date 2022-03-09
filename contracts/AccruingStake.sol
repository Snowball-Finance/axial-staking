// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @title A staking contract which accrues over time based on the amount staked
/// @author Auroter
/// @notice Allows you to lock tokens in exchange for distribution tokens
/// @notice Locks can be deposited into or closed
/// @dev Simply call stake(...) to deposit tokens
/// @dev Call updateAllUsersAccrual(0), then getAccrued(user) / getTotalAccrued() = users share

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
    //uint256 private AprDenominator = 1 days; // Represents rewards accrued // TODO: this may open up an exploit where updating accrual for all users faster than the denominator results in them not getting any accrual

    // Info pertaining to users
    address[] private Users; // An array containing all user addresses
    mapping(address => AccrueVe) private Locks; // A mapping of each users tokens staked
    uint256 private TotalTokensLocked; // Total balance of tokens users have locked
    uint256 private TotalTockensAccrued; // Total balance of accrued tokens currently awarded to users
    uint256 private LastUserIndexUpdated; // Index of the user whose accrual was most recently updated

    struct AccrueVe {
        uint256 TimeStamp; // Last time the accrual was updated
        uint256 StakedTokens; // Quantity of tokens the user has staked
        uint256 AccruedTokens; // Quantity of tokens awarded to the user at time of Timestamp
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
        return Locks[_userAddr].AccruedTokens;
    }

    /// @notice Get the total number of tokens accrued via this contract
    /// @return Quantity of all tokens awarded by this contract
    /// @dev Use this function to get the denominator for a users share of the rewards pool
    function getTotalAccrued() public view returns (uint256) {
        return TotalTockensAccrued;
    }

    /// @notice Retrieve a list of all users who have ever staked
    /// @return An array of addresses of all users who have ever staked
    function getAllUsers() public view returns (address[] memory) {
        return Users;
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
    function claimMyFunds() external nonReentrant {
        address userAddr = msg.sender;
        uint256 fundsToClaim = Locks[userAddr].StakedTokens;

        require(fundsToClaim > 0, "!funds");
        IERC20(StakedToken).safeTransfer(userAddr, fundsToClaim);

        // decrement totals
        TotalTokensLocked -= fundsToClaim;
        TotalTockensAccrued -= Locks[userAddr].AccruedTokens;

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

    /// @notice Deposit tokens into the contract, determining accrual rate
    /// @param _amount Number of tokens to deposit
    function stake(uint256 _amount) public nonReentrant {
        require(_amount > 0, "!amount");

        address userAddr = msg.sender;

        // Receive the users tokens
        require(IERC20(StakedToken).balanceOf(userAddr) >= _amount, "!balance");
        IERC20(StakedToken).safeTransferFrom(userAddr,  address(this), _amount);

        TotalTokensLocked += _amount;

        // Keep track of new users
        if (!Locks[userAddr].Initialized) {
            Users.push(userAddr);
            Locks[userAddr].Initialized = true;
            Locks[userAddr].TimeStamp = block.timestamp; // begin accrual from time of initial deposit
            Locks[userAddr].UserIndex = Users.length - 1;
        } else {
            _updateUsersAccrual(userAddr); // balance ledger before accrual rate is increased
        }

        // Update balance
        Locks[userAddr].StakedTokens += _amount;
    }

    // TODO: This is the bottleneck by design.  Optimize it as much as possible for both our sake and our users.
    // Accrual is tokens locked * seconds
    /// @notice Update the accrual for a specific user
    /// @param _userAddr address of user to update
    /// @dev This will be called by the updateAllUsersAccrual function
    function _updateUsersAccrual(address _userAddr) private {
        uint256 currentTime = block.timestamp;
        uint256 duration = currentTime - Locks[_userAddr].TimeStamp;
        uint256 accrual = duration * Locks[_userAddr].StakedTokens;
        TotalTockensAccrued += accrual;
        Locks[_userAddr].TimeStamp = currentTime;
        Locks[_userAddr].AccruedTokens += accrual;
    }

    // TODO: Consider making this nonreentrant in case staking/withdrawing causes undefined behavior during this operation
    /// @notice Update the accrual for some chunk of users
    /// @param _chunkSize size of chunk to process
    /// @dev Call this however many times is needed to ensure all users accrual is within < 1 day up-to-date
    function updateAllUsersAccrual(uint256 _chunkSize) public {
        uint256 totalUsersLocked = Users.length;
        if (_chunkSize > totalUsersLocked) _chunkSize = totalUsersLocked; // don't update any users more than once
        if (_chunkSize == 0) _chunkSize = totalUsersLocked; // if 0 was passed in, try to update all users

        for (uint256 i = 0; i < _chunkSize; i++) {
            _updateUsersAccrual(Users[LastUserIndexUpdated]);
            LastUserIndexUpdated += 1;
            LastUserIndexUpdated %= totalUsersLocked;
        }
    }

    /// @notice Update the accrual for all users
    /// @notice this has the same effect as calling updateAllUsersAccrual(0)
    // function updateAllUsersAccrual() public {
    //     uint256 totalUsersLocked = Users.length;
    //     updateAllUsersAccrual(totalUsersLocked);
    // }
}
