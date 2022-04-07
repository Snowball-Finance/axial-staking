/// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {ProtocolGovernance} from "./libraries/ProtocolGovernance.sol";
import {Strategist} from "./libraries/Strategist.sol";
import {AccruingStake} from "./AccruingStake.sol";
import {VestingStake} from "./VestingStake.sol";
import {IMasterChefAxialV3} from "./interfaces/IMasterChefAxialV3.sol";
import {AxialDummyToken} from "./AxialDummyToken.sol";
import {Gauge} from "./Gauge.sol";

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract GaugeProxy is ProtocolGovernance {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // ==================== External Dependencies ==================== //

    /// @notice Master Chef Axial V3 contract
    IMasterChefAxialV3 public constant MCAV3 =
        //IMasterChefAxialV3(0x958C0d0baA8F220846d3966742D4Fb5edc5493D3);
        IMasterChefAxialV3(0x35225E5a6309a4823f900EeC047699ecFbE8d341);

    /// @notice token for voting on Axial distribution to pools - SAXIAL
    VestingStake public immutable sAxial;

    /// @notice the Axial token contraxt
    IERC20 public immutable Axial;

    /// @notice dummy token required for masterchef deposits and withdrawals
    IERC20 public immutable axialDummyToken;

    /// @notice token to allow boosting rewards - VEAXIAL
    /// @dev This could be an address instead, as we do not use it other than passing the address to the Gauge constructor
    AccruingStake public immutable veAxial;

    // ==================== Token Voting Storage ==================== //

    /// @notice max time allowed to pass before distribution (6 hours)
    uint256 public constant DISTRIBUTION_DEADLINE = 21600;

    uint256 public constant UINT256_MAX = 2**256-1;
    uint256 public pid = UINT256_MAX;
    uint256 public totalWeight;
    uint256 private lockedTotalWeight;
    uint256 private lockedBalance;
    uint256 private locktime;

    address[] internal _tokens;

    /// @dev token -> gauge
    mapping(address => address) public gauges;
    /// @dev token => gauge
    mapping(address => address) public deprecated;
    /// @dev token => weight
    mapping(address => uint256) public weights;
    /// @dev token => weight
    mapping(address => uint256) private lockedWeights;
    /// @dev msg.sender => token => votes
    mapping(address => mapping(address => uint256)) public votes;
    /// @dev msg.sender => token
    mapping(address => address[]) public tokenVote;
    /// @dev msg.sender => total voting weight of user
    mapping(address => uint256) public usedWeights;
    mapping(address => bool) public deployers;

    constructor(
        address _governance,
        address _axial,
        address _saxial,
        address _veaxial
    ) {
        governance = _governance;
        Axial = IERC20(_axial);
        sAxial = VestingStake(_saxial);
        veAxial = AccruingStake(_veaxial);
        axialDummyToken = new AxialDummyToken();
    }

    // ==================== Admin functions ==================== //

    /// @notice adds the specified address to the list of deployers
    /// @dev deployers can call distribute function
    function addDeployer(address _deployer) external onlyGovernance {
        deployers[_deployer] = true;
    }

    /// @notice removes the specified address from the list of deployers
    function removeDeployer(address _deployer) external onlyGovernance {
        deployers[_deployer] = false;
    }

    // ==================== Modifiers ==================== //

    /// @notice modifier to restrict functinos to governance or strategist roles
    modifier onlyBenevolent() {
        require(msg.sender == governance, "unauthorized sender");
        _;
    }

    // ==================== View functions ==================== //

    /// @notice returns the list of tokens that are currently being voted on
    function tokens() external view returns (address[] memory) {
        return _tokens;
    }

    /// @notice returns the gauge for the specifi(AccruingStake)
    function getGauge(address _token) external view returns (address) {
        return gauges[_token];
    }

    /// @notice returns the number of tokens currently being voted on
    function length() external view returns (uint256) {
        return _tokens.length;
    }

    // ==================== Voting Logic ==================== //

    /// @notice Vote with SAXIAL on a gauge, removing any previous votes
    /// @param _tokenVote: the array of tokens which will recieve tokens
    /// @param _weights: the weights to associate with the tokens listed in _tokenVote
    function vote(address[] calldata _tokenVote, uint256[] calldata _weights)
        external
    {
        require(
            _tokenVote.length == _weights.length,
            "weight/tokenvote length mismatch"
        );
        _vote(msg.sender, _tokenVote, _weights);
    }

    /// @notice internal voting function
    function _vote(
        address _owner,
        address[] memory _tokenVote,
        uint256[] memory _weights
    ) internal {
        // reset votes of the owner
        _reset(_owner);
        uint256 _tokenCnt = _tokenVote.length;
        uint256 _weight = sAxial.getPower(_owner);
        uint256 _totalVoteWeight = 0;
        uint256 _usedWeight = 0;

        for (uint256 i = 0; i < _tokenCnt; i++) {
            _totalVoteWeight = _totalVoteWeight.add(_weights[i]);
        }

        for (uint256 i = 0; i < _tokenCnt; i++) {
            address _token = _tokenVote[i];
            address _gauge = gauges[_token];
            // Calculate quantity of users SAXIAL to allocate for the gauge
            uint256 _tokenWeight = _weights[i].mul(_weight).div(
                _totalVoteWeight
            );

            if (_gauge != address(0x0)) {
                _usedWeight = _usedWeight.add(_tokenWeight);
                totalWeight = totalWeight.add(_tokenWeight);
                weights[_token] = weights[_token].add(_tokenWeight);
                tokenVote[_owner].push(_token);
                votes[_owner][_token] = _tokenWeight;
            }
        }
        usedWeights[_owner] = _usedWeight;
    }

    /// @notice Reset votes of msg.sender to 0
    function reset() external {
        _reset(msg.sender);
    }

    /// @notice Internal function to reset votes of the specified address to 0
    /// @param _owner address of owner of votes to be reset
    function _reset(address _owner) internal {
        // Get all tokens that the owner has voted on
        address[] storage _tokenVote = tokenVote[_owner];
        uint256 _tokenVoteCnt = _tokenVote.length;

        for (uint256 i = 0; i < _tokenVoteCnt; i++) {
            address _token = _tokenVote[i];
            // Get the amount of SAXIAL this user allocated for this specific token
            uint256 _votes = votes[_owner][_token];

            if (_votes > 0) {
                totalWeight = totalWeight.sub(_votes);
                weights[_token] = weights[_token].sub(_votes);

                votes[_owner][_token] = 0;
            }
        }

        delete tokenVote[_owner];
    }

    /// @notice Adjust _owner's votes according to latest _owner's SAXIAL balance
    function poke(address _owner) public {
        address[] memory _tokenVote = tokenVote[_owner];
        uint256 _tokenCnt = _tokenVote.length;
        uint256[] memory _weights = new uint256[](_tokenCnt);

        for (uint256 i = 0; i < _tokenCnt; i++) {
            _weights[i] = votes[_owner][_tokenVote[i]];
        }

        // _weights no longer total 100 like with the front-end
        // But we will minimize gas by not converting
        _vote(_owner, _tokenVote, _weights);
    }

    // ==================== Gauge Logic ==================== //

    /// @notice Add new token gauge
    function addGauge(address _token) external onlyBenevolent {
        require(gauges[_token] == address(0x0), "exists");
        gauges[_token] = address(
            new Gauge(_token, governance, address(veAxial))
        );
        _tokens.push(_token);
    }

    /// @notice Deprecate existing gauge
    function deprecateGauge(address _token) external onlyBenevolent {
        require(gauges[_token] != address(0x0), "does not exist");
        deprecated[_token] = gauges[_token];
        delete gauges[_token];
    }

    /// @notice Bring Deprecated gauge back into use
    function renewGauge(address _token) external onlyBenevolent {
        require(gauges[_token] == address(0x0), "exists");
        require(deprecated[_token] != address(0x0), "not deprecated");
        gauges[_token] = deprecated[_token];
        delete deprecated[_token];
    }

    /// @notice Add existing gauge
    function migrateGauge(address _gauge, address _token)
        external
        onlyBenevolent
    {
        require(gauges[_token] == address(0x0), "exists");
        gauges[_token] = _gauge;
        _tokens.push(_token);
    }

    // ==================== MCAV3 Logic ==================== //

    /// @notice Sets MCAV3 PID
    function setPID(uint256 _pid) external onlyGovernance {
        require(pid == UINT256_MAX, "pid has already been set");
        require(_pid < UINT256_MAX, "invalid pid");
        pid = _pid;
    }

    /// @notice Deposits Axial dummy token into MCAV3
    function deposit() public {
        require(pid < UINT256_MAX, "pid not initialized");
        uint256 _balance = axialDummyToken.balanceOf(address(this));
        axialDummyToken.safeApprove(address(MCAV3), 0);
        axialDummyToken.safeApprove(address(MCAV3), _balance);
        MCAV3.deposit(pid, _balance);
    }

    /// @notice Collects AXIAL from MCAV3 for distribution
    function collect() public {
        (uint256 _locked, ) = MCAV3.userInfo(pid, address(this));
        MCAV3.withdraw(pid, _locked);
        deposit();
    }

    // ==================== Distribution Logic ==================== //

    /// @notice collect AXIAL and update lock information
    function preDistribute() external {
        require(
            deployers[msg.sender] || msg.sender == governance,
            "unauthorized sender"
        );
        lockedTotalWeight = totalWeight;
        for (uint256 i = 0; i < _tokens.length; i++) {
            lockedWeights[_tokens[i]] = weights[_tokens[i]];
        }
        collect();
        lockedBalance = Axial.balanceOf(address(this));
        locktime = block.timestamp;
    }

    /// @notice Distribute tokens to gauges
    function distribute(uint256 _start, uint256 _end) external {
        require(
            deployers[msg.sender] || msg.sender == governance,
            "unauthorized sender"
        );
        require(_start < _end, "bad _start");
        require(_end <= _tokens.length, "bad _end");
        require(
            locktime + DISTRIBUTION_DEADLINE >= block.timestamp,
            "lock expired"
        );
        if (lockedBalance > 0 && lockedTotalWeight > 0) {
            for (uint256 i = _start; i < _end; i++) {
                address _token = _tokens[i];
                address _gauge = gauges[_token];
                uint256 _reward = lockedBalance.mul(lockedWeights[_token]).div(
                    totalWeight
                );
                if (_reward > 0) {
                    Axial.safeApprove(_gauge, 0);
                    Axial.safeApprove(_gauge, _reward);
                    Gauge(_gauge).notifyRewardAmount(_reward);
                }
            }
        }
    }
}
