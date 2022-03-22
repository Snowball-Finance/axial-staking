// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

contract ProtocolGovernance {
    /// @notice address of the governance contract
    address public governance;
    address public pendingGovernance;

    /// @notice modifier to allow for easy gov only control over a function
    modifier onlyGovernance() {
        require(msg.sender == governance, "unauthorized sender (governance");
        _;
    }

    /// @notice Allows governance to change governance (for future upgradability)
    /// @param _governance new governance address to set
    function setGovernance(address _governance) external onlyGovernance {
        pendingGovernance = _governance;
    }

    /// @notice Allows pendingGovernance to accept their role as governance (protection pattern)
    function acceptGovernance() external {
        require(
            msg.sender == pendingGovernance,
            "acceptGovernance: !pendingGov"
        );
        governance = pendingGovernance;
    }
}
