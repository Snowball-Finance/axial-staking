/// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AxialDummyToken is ERC20("AxialDummyToken", "AXD") {
    using SafeMath for uint256;

    constructor() {
        _mint(msg.sender, 1e18);
    }
}
