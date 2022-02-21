// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice this contract is being used in order to allow minting during testing

contract AxialTokenMock is ERC20, Ownable {

    uint256 public maxSupply = 365_000_000e18; // 365 million Axial

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address _to, uint256 _amount) public onlyOwner {
        require(totalSupply() + _amount <= maxSupply, "AXIAL::mint: cannot exceed max supply");
        _mint(_to, _amount);
        //_moveDelegates(address(0), _delegates[_to], _amount);
    }

  function mints(address[] memory tos, uint256[] memory amount) external {
    for (uint i = 0; i < tos.length; i++) {
      mint(tos[i], amount[i]);
    }
  }
}
