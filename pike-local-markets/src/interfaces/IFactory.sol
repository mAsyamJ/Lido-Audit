// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFactory {
    struct PTokenSetup {
        uint256 protocolId;
        address underlying;
        uint256 initialExchangeRateMantissa;
        uint256 reserveFactorMantissa;
        uint256 protocolSeizeShareMantissa;
        uint256 borrowRateMaxMantissa;
        string name;
        string symbol;
        uint8 decimals;
    }

    struct ProtocolInfo {
        uint256 protocolId;
        uint256 numOfMarkets;
        address protocolOwner;
        address initialGovernor;
        address emergencyExecutor;
        address riskEngine;
        address oracleEngine;
        address timelock;
    }

    /**
     * @dev Emitted when a new protocol is deployed.
     * @param protocolId Unique identifier for the deployed protocol.
     * @param riskEngine Address of the deployed Risk Engine contract for the protocol.
     * @param timelock Address of the deployed Timelock contract responsible to
     * deploy new pTokens and configure market parameters.
     * @param initialGovernor Address of the governor for the deployed timelock.
     * @param emergencyExecutor Address of the gurdian for the timelock emergency guardian.
     */
    event ProtocolDeployed(
        uint256 indexed protocolId,
        address indexed riskEngine,
        address indexed timelock,
        address oracleEngine,
        address initialGovernor,
        address emergencyExecutor
    );

    /**
     * @dev Emitted when a new PToken is successfully deployed for a protocol.
     * @param protocolId Unique identifier of the protocol associated with the PToken.
     * @param index The index of the PToken within the protocol to track.
     * @param pToken Address of the deployed PToken proxy.
     * @param timelock Address of the Timelock contract assigned as pToken configurator.
     */
    event PTokenDeployed(
        uint256 indexed protocolId,
        uint256 indexed index,
        address indexed pToken,
        address timelock
    );

    /// revert when caller has not assigned as configurator
    error UnauthorizedMarketDeployment();

    /**
     * @dev The function is called by protocol owner governance to deploy new protocol
     * @dev Deploys a new risk/oracle engine with protocol owner as default owner
     * @dev Deploys a new timelock and set governor as default admin and set
     * access on timelock to manage risk engine in order to modify markets
     * @param governor address of governor that is set as proposer of timelock contract
     * @param guardian address of emergency guardian that is set as emergency executor of timelock contract
     * @param ownerShareMantissa percentage of accumulated reserve that reserve for protocol owner
     * @param configuratorShareMantissa percentage of accumulated reserve that reserve for governor
     */
    function deployProtocol(
        address governor,
        address guardian,
        uint256 ownerShareMantissa,
        uint256 configuratorShareMantissa
    )
        external
        returns (
            address riskEngine,
            address oracleEngine,
            address payable governorTimelock
        );

    /**
     * @dev Deploys a new pToken for the deployed protocol
     * and connects it to protocol risk engine
     * @dev Inititalize the pToken with given risk parameters
     * @dev Protocol owner will be the default owner of pToken
     * @dev assigned timelock will be the core configurator of pToken
     * @param setupParams struct with initial risk params of pToken
     * @return pToken address of deployed proxy contract
     */
    function deployMarket(PTokenSetup memory setupParams)
        external
        returns (address pToken);

    /**
     * @notice Returns the address of the risk engine beacon.
     */
    function riskEngineBeacon() external view returns (address);

    /**
     * @notice Returns the address of the oracle engine beacon.
     */
    function oracleEngineBeacon() external view returns (address);

    /**
     * @notice Returns the address of the pToken beacon.
     */
    function pTokenBeacon() external view returns (address);

    /**
     * @notice Returns the address of the timelock beacon.
     */
    function timelockBeacon() external view returns (address);

    /**
     * @notice Returns the total number of deployed protocols.
     * @dev protocol ids start from 1
     */
    function protocolCount() external view returns (uint256);

    /**
     * @notice Fetches the information of a protocol by its ID.
     * @param protocolId The ID of the protocol.
     */
    function getProtocolInfo(uint256 protocolId)
        external
        view
        returns (ProtocolInfo memory);

    /**
     * @notice Fetches the address of a market (pToken) by protocol ID and index.
     * @param protocolId The ID of the protocol.
     * @param index The index of deployed pToken starting from 0
     * @return The address of the specified market.
     */
    function getMarket(uint256 protocolId, uint256 index)
        external
        view
        returns (address);
}
