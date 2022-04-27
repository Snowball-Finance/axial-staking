/// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Master Chef V2(MCAV2) interface
/// @notice Interface for the MCAV2 contract that will control minting of AXIAL
interface IMasterChef {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. AXIALs to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that AXIALs distribution occurs.
        uint256 accAxialPerShare; // Accumulated AXIALs per share, times 1e12. See below.
    }

    function poolInfo(uint256 pid) external view returns (IMasterChef.PoolInfo memory);

    function totalAllocPoint() external view returns (uint256);

    function axialPerSec() external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function devPercent() external view returns (uint256);

    function treasuryPercent() external view returns (uint256);

    function investorPercent() external view returns (uint256);

    function userInfo(uint256 pid, address addr) external view returns (uint256, uint256);

    function withdraw(uint256 pid, uint256 amount) external;
}
