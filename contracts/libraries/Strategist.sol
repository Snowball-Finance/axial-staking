// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

contract Strategist {
    /// @notice strategist address for the strategist contract
    address public strategist;
    address public pendingStrategist;

    /// @notice modifier to allow for easy gov only control over a function
    modifier onlyStrategist() {
        require(msg.sender == strategist, "unauthorized sender (strategist)");
        _;
    }

    /// @notice Allows strategist to change strategist (for future upgradability)
    /// @param _strategist new strategist address to set
    function setStrategist(address _strategist) external onlyStrategist {
        pendingStrategist = _strategist;
    }

    /// @notice Allows pendingStrategist to accept their role as strategist
    function acceptStrategist() external {
        require(
            msg.sender == pendingStrategist,
            "unauthorized sender (pendingStrategist)"
        );
        strategist = pendingStrategist;
    }
}
