/// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @notice Temporary interface for VeAxial
/// @dev Should be removed once the VeAxial contract merged to the main branch and can be pulled into gauge-proxy reature branch
interface IVeAxial {
    /// @notice Get the total number of tokens a user has accrued
    function getAccrued(address _userAddr) external view returns (uint256);

    /// @notice Get the total number of tokens accrued via this contract
    function getTotalAccrued() external view returns (uint256);
}
