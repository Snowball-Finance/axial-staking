// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @title Equity management contract with lockouts
/// @author Auroter
/// @notice Allows you to allocate equity for users
/// @notice Equity pool can be expanded over time

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EquityStake is Ownable {
    using SafeERC20 for IERC20;

    // Info pertaining to staking contract
    address[] public stakedTokens; // ERC20 tokens to be staked (i.e. Axial)
    mapping(address => uint256) numTokens; // Balance of staked tokens, token => balance
    uint256 unallocatedPercentage = 100; // Percentage of unallocated equity
    string public name; // Equity asset name (i.e. eAxial)
    string public symbol; // Equity asset symbol (i.e. eAXIAL)
    uint256 private interpolationGranularity = 1e18; // Note: ERC20.decimals() is for display and does not affect arithmetic!

    // Info pertaining to users
    address[] private users; // An array containing all user addresses
    mapping(address => Lock) private locks; // A mapping of each users lock

    // Lock structure, only one of these is allowed per user
    struct Lock {
        uint256 startBlockTime;
        uint256 endBlockTime;
        uint256 percentEquity;
        bool initialized;
    }

    /// @notice Constructor
    /// @param _name Desired name of our equity token
    /// @param _symbol Desired symbol of our equity token
    /// @param _governance Address of wallet which will be given adminstrative access to this contract
    constructor(
        string memory _name,
        string memory _symbol,
        address _governance
    ) {
        transferOwnership(_governance);
        name = _name;
        symbol = _symbol;
    }

    /// @notice Emitted when a user is given equity
    /// @param user Address of the user who was given equity
    /// @param percent percentage of equity given
    /// @param duration Length in seconds of lockout
    event equityAwarded(address indexed user, uint256 percent, uint256 duration);

    /// @notice Emitted when equity is deposited into the contract
    /// @param token Address of staked token
    /// @param amount New total quantity of tokens in stake
    event equityDeposited(address indexed token, uint256 amount);

    /// @notice Emitted when a user claims their equity tokens
    /// @param user Address of the user who claimed
    /// @param token Address of the claimed token
    /// @param amount Quantity of tokens claimed
    event equityClaimed(address indexed user, address indexed token, uint256 amount);

    /// @notice Allow owner to reclaim tokens not matching the deposit token
    /// @notice Some users may have accidentally sent these to the contract
    /// @param _token Address of the non-deposit token
    /// @dev Always ensure the _token is legitimate before calling this
    /// @dev A bad token can mimic safetransfer or balanceof with a nocive function
    /// @dev If tokens were accidentally sent directly to the contract they can also be removed
    function ownerRemoveNonDepositToken(address _token) public nonReentrant onlyOwner {
        uint256 balanceOfToken = IERC20(_token).balanceOf(address(this));
        require(stakedTokens[_token] < balanceOfToken, "Token was not accidentally sent to this contract");
        uint256 toWithdraw = balanceOfToken - stakedTokens[_token];
        require(toWithdraw > 0, "!balance");
        IERC20(_token).safeTransfer(owner(), toWithdraw);
    }

    /// @notice Compute the number of seconds in a week
    /// @notice useful for awarding equity
    /// @param _weeks the number of weeks to convert into seconds
    /// @return _weeks represented in seconds
    function getWeeksInSeconds(uint256 _weeks) external pure returns (uint256) {
        return 60 * 60 * 24 * 7 * _weeks;
    }

    /// @notice Allocate equity share for a user\
    /// @param _user the user we wish to allocate equity for
    /// @param _percent the percent share we wish to *add* for the user
    /// @param _lockDuration time the user has to wait before they can claim their equity
    function awardEquity(address _user, uint256 _percent, uint256 _lockDuration) public onlyOwner {
        require(_percent > 0, "Cannot allocate 0");
        require(unallocatedPercentage <= _percent, "Not enough equity available");
        unallocatedPercentage -= _percent;

        uint256 currentTime = block.timestamp;

        Lock memory lock = locks[_user];
        if (!lock.initialized) {
            lock.initialized = true;
            lock.startBlockTime = currentTime;
        } else {
            require(lock.startBlockTime + _lockDuration >= lock.endBlockTime, "Cannot shorten lockout");
        }

        lock.percentEquity += _percent;
        lock.endBlockTime = lock.startBlockTime + _lockDuration;

        locks[_user] = lock;

        emit equityAwarded(_user, lock.percentEquity, _lockDuration);
    }

    /// @notice Deposit any token into the contracts equity pool
    /// @param _token Address of the token we wish to deposit
    /// @param _amount quantity of the token we wish to deposit
    /// @dev Tokens sent directly to this contract will be lost forever.  todo: allow withdrawal of balanceOf tokens not accounted for via this function
    function depositEquity(address _token, uint256 _amount) public onlyOwner {
        address userAddr = msg.sender;

        // Receive the tokens
        require(IERC20(_token).balanceOf(userAddr) >= _amount, "!balance");
        require(IERC20(_token).allowance(userAddr, address(this)) >= _amount, "!approved");
        IERC20(_token).safeTransferFrom(userAddr,  address(this), _amount);

        if (numTokens[_token] == 0) {
            stakedTokens.push(_token);
        }

        numTokens[_token] += _amount;

        emit equityDeposited(_token, numTokens[_token]);
    }

    /// @notice allow the user to claim their equity once their lock has expired
    function claimEquity() public {
        address userAddr = msg.sender;
        Lock storage lock = locks[userAddr];
        require(lock.initialized, "User not found");
        require(lock.endBlockTime < block.timestamp, "Equity is still locked");

        uint256 equity = lock.percentEquity;
        lock.percentEquity = 0;

        for (uint256 i = 0; i < stakedTokens.length; ++i) {
            address token = stakedTokens[i];
            uint256 fundsToClaim = numTokens[token] * equity / 100;
            IERC20(token).safeTransfer(userAddr, fundsToClaim);
            emit equityClaimed(userAddr, token, fundsToClaim);
        }

        unallocatedPercentage += equity;
    }


}
