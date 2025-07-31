// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IPToken} from "@interfaces/IPToken.sol";
import {IRBAC} from "@interfaces/IRBAC.sol";
import {IOwnable} from "@interfaces/IOwnable.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Timelock} from "@governance/Timelock.sol";
import {UUPSUpgradeable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";
import {InitialModuleBeacon} from "@modules/InitialModuleBeacon.sol";
import {PTokenModule} from "@modules/pToken/PTokenModule.sol";
import {OracleEngine} from "@oracles/OracleEngine.sol";

/**
 * @title Pike Markets Factory Contract
 * @author NUTS Finance (hello@pike.finance)
 */
contract Factory is
    IFactory,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /// @custom:storage-location erc7201:pike.facotry
    struct FactoryStorage {
        /**
         * @dev Incremental unique identifier for deployed protocol, used as protocol Id
         */
        uint256 protocolCount;
        /**
         * @dev Beacon for the RiskEngine implementation.
         */
        address riskEngineBeacon;
        /**
         * @dev Beacon for the OracleEngine implementation.
         */
        address oracleEngineBeacon;
        /**
         * @dev Beacon for the Timelock implementation.
         */
        address timelockBeacon;
        /**
         * @dev Beacon for the PToken implementation.
         */
        address pTokenBeacon;
        /**
         * @dev mapping protocol id -> protocol info
         */
        mapping(uint256 => ProtocolInfo) protocolRegistry;
        /**
         * @dev mapping protocol id -> index -> pToken
         */
        mapping(uint256 => mapping(uint256 => address)) markets;
        bytes32[7] permissions;
    }

    bytes32 internal constant _CONFIGURATOR_PERMISSION = "CONFIGURATOR";
    bytes32 internal constant _PROTOCOL_OWNER_PERMISSION = "PROTOCOL_OWNER";
    bytes32 internal constant _OWNER_WITHDRAWER_PERMISSION = "OWNER_WITHDRAWER";
    bytes32 internal constant _BORROW_CAP_GUARDIAN_PERMISSION = "BORROW_CAP_GUARDIAN";
    bytes32 internal constant _SUPPLY_CAP_GUARDIAN_PERMISSION = "SUPPLY_CAP_GUARDIAN";
    bytes32 internal constant _RESERVE_MANAGER_PERMISSION = "RESERVE_MANAGER";
    bytes32 internal constant _RESERVE_WITHDRAWER_PERMISSION = "RESERVE_WITHDRAWER";

    /// keccak256(abi.encode(uint256(keccak256("pike.factory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _FACTORY_STORAGE =
        0x2123ddb3bc0e3ddb579620b217a9df111470695d13bf4198d6177cfc5622e800;

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the Pike Market factory contract.
     */
    function initialize(
        address _initialOwner,
        address _riskEngineBeacon,
        address _oracleEngineBeacon,
        address _pTokenBeacon,
        address _timelockBeacon
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_initialOwner);
        FactoryStorage storage $ = _getFactoryStorage();

        $.riskEngineBeacon = _riskEngineBeacon;
        $.oracleEngineBeacon = _oracleEngineBeacon;
        $.pTokenBeacon = _pTokenBeacon;
        $.timelockBeacon = _timelockBeacon;
        $.permissions = [
            _PROTOCOL_OWNER_PERMISSION,
            _OWNER_WITHDRAWER_PERMISSION,
            _CONFIGURATOR_PERMISSION,
            _BORROW_CAP_GUARDIAN_PERMISSION,
            _SUPPLY_CAP_GUARDIAN_PERMISSION,
            _RESERVE_MANAGER_PERMISSION,
            _RESERVE_WITHDRAWER_PERMISSION
        ];
    }

    /**
     * @inheritdoc IFactory
     */
    function deployProtocol(
        address initialGovernor,
        address emergencyExecutor,
        uint256 ownerShareMantissa,
        uint256 configuratorShareMantissa
    )
        external
        onlyOwner
        returns (
            address riskEngine,
            address oracleEngine,
            address payable governorTimelock
        )
    {
        FactoryStorage storage $ = _getFactoryStorage();
        // initiate timelock with governor address as proposer and executor
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = initialGovernor;
        executors[0] = address(0); // open to execute
        bytes memory timelockInit = abi.encodeCall(
            Timelock.initialize,
            (address(0), owner(), emergencyExecutor, 1 days, proposers, executors)
        );
        governorTimelock =
            payable(address(new BeaconProxy($.timelockBeacon, timelockInit)));

        // initiate risk engine
        bytes memory riskEngineInit =
            abi.encodeCall(InitialModuleBeacon.initialize, (address(this)));
        riskEngine = address(new BeaconProxy($.riskEngineBeacon, riskEngineInit));

        // initiate oracle engine with timelock as configurator
        bytes memory oracleEngineInit =
            abi.encodeCall(OracleEngine.initialize, (owner(), governorTimelock));
        oracleEngine = address(new BeaconProxy($.oracleEngineBeacon, oracleEngineInit));

        // set oracle engine
        IRiskEngine(riskEngine).setOracle(address(oracleEngine));
        // set owner and governor share percentage
        IRiskEngine(riskEngine).setReserveShares(
            ownerShareMantissa, configuratorShareMantissa
        );

        // set Governor timelock permissions
        for (uint256 i = 2; i < $.permissions.length; i++) {
            IRBAC(riskEngine).grantPermission($.permissions[i], governorTimelock);
        }

        // set protocol owner permission
        IRBAC(riskEngine).grantPermission($.permissions[0], owner());
        // set protocol owner permission
        IRBAC(riskEngine).grantPermission($.permissions[1], owner());
        // set configurator permission for factory
        IRBAC(riskEngine).grantPermission($.permissions[2], address(this));
        // transfer ownership to protocol owner
        IOwnable(riskEngine).transferOwnership(owner());

        ProtocolInfo storage protocolInfo = $.protocolRegistry[++$.protocolCount];
        protocolInfo.protocolId = $.protocolCount;
        protocolInfo.initialGovernor = initialGovernor;
        protocolInfo.emergencyExecutor = emergencyExecutor;
        protocolInfo.riskEngine = riskEngine;
        protocolInfo.oracleEngine = oracleEngine;
        protocolInfo.timelock = governorTimelock;
        protocolInfo.protocolOwner = owner();

        emit ProtocolDeployed(
            protocolInfo.protocolId,
            riskEngine,
            governorTimelock,
            oracleEngine,
            protocolInfo.initialGovernor,
            protocolInfo.emergencyExecutor
        );
    }

    /**
     * @inheritdoc IFactory
     */
    function deployMarket(PTokenSetup memory setupParams)
        external
        nonReentrant
        returns (address pToken)
    {
        FactoryStorage storage $ = _getFactoryStorage();
        ProtocolInfo memory protocolInfo = $.protocolRegistry[setupParams.protocolId];
        if (!IRBAC(protocolInfo.riskEngine).hasPermission($.permissions[2], msg.sender)) {
            revert UnauthorizedMarketDeployment();
        }

        bytes memory pTokenInit =
            abi.encodeCall(InitialModuleBeacon.initialize, (address(this)));
        pToken = address(new BeaconProxy($.pTokenBeacon, pTokenInit));

        // initiate pToken
        PTokenModule(pToken).initialize(
            setupParams.underlying,
            IRiskEngine(protocolInfo.riskEngine),
            setupParams.initialExchangeRateMantissa,
            setupParams.reserveFactorMantissa,
            setupParams.protocolSeizeShareMantissa,
            setupParams.borrowRateMaxMantissa,
            setupParams.name,
            setupParams.symbol,
            setupParams.decimals
        );
        // transfer ownership to protocol owner
        IOwnable(pToken).transferOwnership(owner());
        // set pToken in risk engine
        IRiskEngine(protocolInfo.riskEngine).supportMarket(IPToken(pToken));

        uint256 index = $.protocolRegistry[setupParams.protocolId].numOfMarkets++;
        $.markets[protocolInfo.protocolId][index] = pToken;

        emit PTokenDeployed(protocolInfo.protocolId, index, pToken, protocolInfo.timelock);
    }

    /**
     * @inheritdoc IFactory
     */
    function riskEngineBeacon() external view returns (address) {
        return _getFactoryStorage().riskEngineBeacon;
    }

    /**
     * @inheritdoc IFactory
     */
    function oracleEngineBeacon() external view returns (address) {
        return _getFactoryStorage().oracleEngineBeacon;
    }

    /**
     * @inheritdoc IFactory
     */
    function pTokenBeacon() external view returns (address) {
        return _getFactoryStorage().pTokenBeacon;
    }

    /**
     * @inheritdoc IFactory
     */
    function timelockBeacon() external view returns (address) {
        return _getFactoryStorage().timelockBeacon;
    }

    /**
     * @inheritdoc IFactory
     */
    function protocolCount() external view returns (uint256) {
        return _getFactoryStorage().protocolCount;
    }

    /**
     * @inheritdoc IFactory
     */
    function getProtocolInfo(uint256 protocolId)
        external
        view
        returns (ProtocolInfo memory)
    {
        return _getFactoryStorage().protocolRegistry[protocolId];
    }

    /**
     * @inheritdoc IFactory
     */
    function getMarket(uint256 protocolId, uint256 index)
        external
        view
        returns (address)
    {
        return _getFactoryStorage().markets[protocolId][index];
    }

    /**
     * @notice Authorize upgrade
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _getFactoryStorage() internal pure returns (FactoryStorage storage data) {
        bytes32 s = _FACTORY_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
