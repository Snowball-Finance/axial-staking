// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @title A vesting style staking contract with extendable linear decay
/// @author Auroter
/// @notice Allows you to lock tokens in exchange for governance tokens
/// @notice Locks can be extended or deposited into
/// @notice Maximum deposit duration is two years (104 weeks)
/// @dev Simply call stake(...) to create initial lock or extend one that already exists for the user

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//import "hardhat/console.sol";

contract VestingStake is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Info pertaining to staking contract
    address public stakedToken; // An ERC20 Token to be staked (i.e. Axial)
    string public name; // New asset after staking (i.e. sAxial)
    string public symbol; // New asset symbol after staking (i.e. sAXIAL)
    uint256 private interpolationGranularity = 1e18; // Note: ERC20.decimals() is for display and does not affect arithmetic!

    // Info pertaining to users
    address[] private users; // An array containing all user addresses
    mapping(address => LockVe) private locks; // A mapping of each users lock
    mapping(address => uint256) private lockedFunds; // A mapping of each users total deposited funds
    mapping(address => uint256) private deferredFunds; // A mapping of vested funds the user wishes to leave unclaimed

    // Lock structure, only one of these is allowed per user
    // A DELTA can be derived as the degree of interpolation between the start/end block:
    // Delta = (end - now) / end - start
    // This can be used to determine how much of our staked token is unlocked:
    // currentAmountLocked = startingAmountLocked - (delta * startingAmountLocked)
    struct LockVe {
        uint256 startBlockTime;
        uint256 endBlockTime;
        uint256 startingAmountLocked;
        bool initialized;
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
        stakedToken = _stakedToken;
        name = _name;
        symbol = _symbol;
    }

    /// @notice Emitted when a user stakes for the first time
    /// @param user Address of the user who staked
    /// @param amount Quantity of tokens staked
    /// @param duration Length in seconds of stake
    event userStaked(address indexed user, uint256 amount, uint256 duration);

    /// @notice Emitted when a user extends and/or deposits into their existing stake
    /// @param user Address of the user who staked
    /// @param amount New total quantity of tokens in stake
    /// @param duration New total length of stake
    event userExtended(address indexed user, uint256 amount, uint256 duration);

    /// @notice Emitted when a user claims outstanding vested balance
    /// @param user Address of the user who claimed
    /// @param amount Quantity of tokens claimed
    event userClaimed(address indexed user, uint256 amount);

    /// @notice Calculate the number of vested tokens a user has not claimed
    /// @param _userAddr Address of any user to view the number of vested tokens they have not yet claimed
    /// @return Quantity of tokens which have vested but are unclaimed by the specified user
    function getUnclaimed(address _userAddr) public view returns (uint256) {
        uint256 totalFundsDeposited = lockedFunds[_userAddr] + deferredFunds[_userAddr];
        uint256 currentBalance = getBalance(_userAddr);
        uint256 fundsToClaim = totalFundsDeposited - currentBalance;
        return fundsToClaim;
    }

    /// @notice Calculate the number of tokens a user still has locked
    /// @param _userAddr Address of any user to view the number of tokens they still have locked
    /// @return Quantity of tokens the user has locked
    function getBalance(address _userAddr) public view returns (uint256) {
        LockVe memory usersLock = locks[_userAddr];

        uint256 currentTimestamp = block.timestamp;
        uint256 balance = 0;

        if (usersLock.endBlockTime > currentTimestamp) {
            uint256 granularDelta = ((usersLock.endBlockTime - currentTimestamp) * interpolationGranularity) / (usersLock.endBlockTime - usersLock.startBlockTime);
            balance += (usersLock.startingAmountLocked * granularDelta) / interpolationGranularity;
        }
        return balance;
    }

    /// @notice Calculate the number of governance tokens currently allocated to a user by this contract
    /// @param _userAddr Address of any user to view the number of governance tokens currently awarded to them
    /// @return Quantity of governance tokens allocated to the user
    function getPower(address _userAddr) public view returns (uint256) {
        LockVe memory usersLock = locks[_userAddr];

        uint256 currentTimestamp = block.timestamp;
        uint256 power = 0;

        if (usersLock.endBlockTime > currentTimestamp) {
            // let delta = elapsed / totalLocktinme
            // let startingPower = duration / 2 years
            // let power = delta * startingPower
            uint256 startingAmountAwarded = ((usersLock.endBlockTime - usersLock.startBlockTime) * usersLock.startingAmountLocked) / 104 weeks;
            uint256 granularDelta = ((usersLock.endBlockTime - currentTimestamp) * interpolationGranularity) / (usersLock.endBlockTime - usersLock.startBlockTime);
            power += (startingAmountAwarded * granularDelta) / interpolationGranularity;
        }
        return power;
    }

    /// @notice Retrieve a list of all users who have ever staked
    /// @return An array of addresses of all users who have ever staked
    function getAllUsers() public view returns (address[] memory) {
        return users;
    }

    /// @notice Check if a user has ever created a Lock in this contract
    /// @param _userAddr Address of any user to check
    /// @dev This may be used by the web application to determine if the UI says "Create Lock" or "Add to Lock"
    /// @return True if the user has ever created a lock
    function isUserLocked(address _userAddr) public view returns (bool) {
        LockVe memory usersLock = locks[_userAddr];
        return usersLock.initialized;
    }

    /// @notice View a users Lock
    /// @param _userAddr Address of any user to view all Locks they have ever created
    /// @dev This may be used by the web application for graphical illustration purposes
    /// @return Users Lock in the format of the LockVe struct
    function getLock(address _userAddr) public view returns (LockVe memory) {
        return locks[_userAddr];
    }

    /// @notice Allow owner to reclaim tokens not matching the deposit token
    /// @notice Some users may have accidentally sent these to the contract
    /// @param _token Address of the non-deposit token
    function ownerRemoveNonDepositToken(address _token) public nonReentrant onlyOwner {
        require(_token != stakedToken, "!invalid");
        uint256 balanceOfToken = IERC20(_token).balanceOf(address(this));
        require(balanceOfToken > 0, "!balance");
        IERC20(_token).safeTransfer(owner(), balanceOfToken);
    }

    /// @notice Transfers vested tokens back to their original owner
    /// @notice It is up to the user to invoke this manually
    /// @dev This will need to be called by the web application via a button or some other means
    function claimMyFunds() external nonReentrant {
        address userAddr = msg.sender;
        uint256 totalFundsDeposited = lockedFunds[userAddr] + deferredFunds[userAddr];
        uint256 currentBalance = getBalance(userAddr);
        uint256 fundsToClaim = totalFundsDeposited - currentBalance;

        IERC20(stakedToken).safeTransfer(userAddr, fundsToClaim);

        lockedFunds[userAddr] = currentBalance;
        deferredFunds[userAddr] = 0;

        emit userClaimed(userAddr, fundsToClaim);
    }

    /// @notice Create/extend the duration of the invoking users lock and/or deposit additional tokens into it
    /// @param _duration Number of seconds the invoking user will extend their lock for
    /// @param _amount Number of additional tokens to deposit into the lock
    /// @param _deferUnclaimed If True, leaves any unclaimed vested balance in the staking contract
    function stake(uint256 _duration, uint256 _amount, bool _deferUnclaimed) public nonReentrant {
        require(_duration > 0 || _amount > 0, "null");

        // Retrieve lock the user may have already created
        address userAddr = msg.sender;
        LockVe memory usersLock = locks[userAddr];

        uint256 oldDurationRemaining = 0;

        // Keep track of new user or pre-existing lockout period
        if (!usersLock.initialized) {
            users.push(userAddr);
        } else if (block.timestamp < usersLock.endBlockTime) {
            oldDurationRemaining = usersLock.endBlockTime - block.timestamp;
        }

        require (oldDurationRemaining + _duration <= 104 weeks, ">2 years");

        // Receive the users tokens
        require(IERC20(stakedToken).balanceOf(userAddr) >= _amount, "!balance");
        require(IERC20(stakedToken).allowance(userAddr, address(this)) >= _amount, "!approved");
        IERC20(stakedToken).safeTransferFrom(userAddr,  address(this), _amount);

        // Account for balance / unclaimed funds
        uint256 totalFundsDeposited = lockedFunds[userAddr];
        uint256 oldBalance = getBalance(userAddr);
        uint256 fundsUnclaimed = totalFundsDeposited - oldBalance;
        if (!_deferUnclaimed) {
            fundsUnclaimed += deferredFunds[userAddr];
            IERC20(stakedToken).safeTransfer(userAddr, fundsUnclaimed);
            deferredFunds[userAddr] = 0;
            emit userClaimed(userAddr, fundsUnclaimed);
        } else {
            deferredFunds[userAddr] += fundsUnclaimed;
        }
        uint256 newTotalDeposit = oldBalance + _amount;

        // Update balance
        lockedFunds[userAddr] = newTotalDeposit;

        // Fill out updated LockVe struct
        LockVe memory newLock;
        newLock.startBlockTime = block.timestamp;
        newLock.endBlockTime = newLock.startBlockTime + _duration + oldDurationRemaining;
        newLock.startingAmountLocked = newTotalDeposit;
        newLock.initialized = true;
        locks[userAddr] = newLock;

        // Events
        if (oldDurationRemaining == 0) {
            emit userStaked(userAddr, newTotalDeposit, newLock.endBlockTime - newLock.startBlockTime);
        } else {
            emit userExtended(userAddr, newTotalDeposit, newLock.endBlockTime - newLock.startBlockTime);
        }
    }
}
