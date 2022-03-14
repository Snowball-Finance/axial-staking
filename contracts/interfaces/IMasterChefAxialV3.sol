/// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @title Master Chef V3(MCAV3) interface
/// @notice Interface for the MCAV3 contract that will control minting of AXIAL via MCAV2
interface IMasterChefAxialV3 {
    /// @notice Deposit LP tokens to MCAV3 for AXIAL allocation.
    function deposit(uint256 _pid, uint256 _amount) external;

    /// @notice Withdraw LP tokens from MCAV3
    function withdraw(uint256 pid, uint256 amount) external;

    /// @notice Get the pool user info for the address provided
    function userInfo(uint256 pid, address owner)
        external
        view
        returns (uint256 amount, uint256 rewardDebt);
}
