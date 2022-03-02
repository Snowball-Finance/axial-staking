// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @title Axial staking contract with extendable linear decay
/// @author Auroter
/// @dev See also VestingStake.sol

import "./VestingStake.sol";

contract StakedAxialToken is VestingStake {
    address constant private AxialTokenAddress = 0xcF8419A615c57511807236751c0AF38Db4ba3351;
    string constant private GovernanceTokenName = "StakedAxialToken";
    string constant private GovernanceTokenSymbol = "sAXIAL";
    address constant private OwnerAddress = 0xfdCcf6D49A29f435E509DFFAAFDecB0ADD93f8C0;

    /// @notice Constructor
    constructor() VestingStake(AxialTokenAddress, GovernanceTokenName, GovernanceTokenSymbol, OwnerAddress) {}
}