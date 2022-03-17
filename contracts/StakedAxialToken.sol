// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @title Axial staking contract with extendable linear decay
/// @author Auroter
/// @dev See also VestingStake.sol

import "./VestingStake.sol";

contract StakedAxialToken is VestingStake {
    address public immutable AxialTokenAddress;

    string private constant GovernanceTokenName = "StakedAxialToken";
    string private constant GovernanceTokenSymbol = "sAXIAL";
    address private constant OwnerAddress =
        0xfdCcf6D49A29f435E509DFFAAFDecB0ADD93f8C0;

    /// @notice Constructor
    constructor(address _axialTokenAddress)
        VestingStake(
            _axialTokenAddress,
            GovernanceTokenName,
            GovernanceTokenSymbol,
            OwnerAddress
        )
    {
        AxialTokenAddress = _axialTokenAddress;
    }
}
