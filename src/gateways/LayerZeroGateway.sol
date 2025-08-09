// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { OApp } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { OAppRead } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppRead.sol";
import { Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {
    MessagingReceipt,
    MessagingFee,
    MessagingParams,
    ILayerZeroEndpointV2
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { IGateway } from "../interfaces/IGateway.sol";
import { IGatewayApp } from "../interfaces/IGatewayApp.sol";
import { ILiquidityMatrix } from "../interfaces/ILiquidityMatrix.sol";

/**
 * @title LayerZeroGateway
 * @notice LayerZero-based implementation of the IGateway interface for cross-chain communication
 * @dev Implements cross-chain read operations and messaging using LayerZero v2 protocol.
 *      Manages app registration, read target configuration, and handles both outbound reads
 *      and inbound message routing. Converts between generic bytes32 chainUID and LayerZero uint32 eid internally.
 *      Supports both cross-chain reads with lzReduce aggregation and direct messaging between chains.
 */
contract LayerZeroGateway is OApp, OAppRead, ReentrancyGuard, IGateway {
    using OptionsBuilder for bytes;

    struct AppState {
        uint16 cmdLabel;
        mapping(uint32 eid => bytes32) targets;
    }

    struct ReadRequest {
        address app;
        bytes extra;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint32 public immutable READ_CHANNEL;
    address public immutable liquidityMatrix;

    // Chain configuration
    uint32[] internal _targetEids;
    mapping(uint32 => uint16) internal _chainConfigConfirmations;

    mapping(address app => AppState) public appStates;
    mapping(uint16 cmdLabel => address app) public getApp;
    mapping(uint32 eid => uint64) public transferDelays;

    uint16 internal _lastCmdLabel;
    mapping(bytes32 guid => ReadRequest) public readRequests;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterApp(address indexed app, uint16 indexed cmdLabel);
    event UpdateTransferDelay(uint32 indexed eid, uint64 delay);
    event UpdateReadTarget(address indexed app, uint32 indexed eid, bytes32 indexed target);
    event MessageSent(uint32 indexed eid, bytes32 indexed guid, bytes message);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Forbidden();
    error InvalidApp();
    error InvalidTarget();
    error InvalidLengths();
    error InvalidChainUID();
    error InvalidLzReadOptions();
    error InvalidGuid();
    error InvalidCmdLabel();
    error InvalidRequests();
    error DuplicateTargetEid();

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyApp() {
        if (appStates[msg.sender].cmdLabel == 0) revert Forbidden();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the LayerZeroGateway contract with the necessary configurations.
     * @param _readChannel The read channel ID for LayerZero communication.
     * @param _endpoint The LayerZero endpoint address.
     * @param _liquidityMatrix The LiquidityMatrix contract address.
     * @param _owner The address that will be granted ownership privileges.
     */
    constructor(uint32 _readChannel, address _endpoint, address _liquidityMatrix, address _owner)
        OAppRead(_endpoint, _owner)
        Ownable(_owner)
    {
        READ_CHANNEL = _readChannel;
        liquidityMatrix = _liquidityMatrix;

        _setPeer(READ_CHANNEL, AddressCast.toBytes32(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current chain configuration
     * @return chainUIDs Array of configured chain UIDs
     * @return confirmations Array of confirmation requirements for each chain
     */
    function chainConfigs() public view returns (bytes32[] memory chainUIDs, uint16[] memory confirmations) {
        uint256 length = _targetEids.length;
        chainUIDs = new bytes32[](length);
        confirmations = new uint16[](length);
        for (uint256 i; i < length; i++) {
            chainUIDs[i] = bytes32(uint256(_targetEids[i]));
            confirmations[i] = _chainConfigConfirmations[_targetEids[i]];
        }
    }

    /**
     * @notice Returns the number of configured chains
     * @return The length of configured chains
     */
    function chainUIDsLength() public view returns (uint256) {
        return _targetEids.length;
    }

    /**
     * @notice Returns the chain UID at a specific index
     * @param index The index to query
     * @return The chain UID at the given index
     */
    function chainUIDAt(uint256 index) public view returns (bytes32) {
        return bytes32(uint256(_targetEids[index]));
    }

    /**
     * @notice Quotes the messaging fee for sending a read request with specific calldata.
     * @param gasLimit The gas limit to allocate for actual transfer after read completion.
     * @return fee The estimated messaging fee for the request.
     */
    function quoteRead(address app, bytes memory callData, uint32 returnDataSize, uint128 gasLimit)
        public
        view
        returns (uint256 fee)
    {
        (bytes32[] memory chainUIDs,) = chainConfigs();
        uint32[] memory eids = new uint32[](chainUIDs.length);
        for (uint256 i; i < chainUIDs.length; i++) {
            eids[i] = uint32(uint256(chainUIDs[i]));
        }
        MessagingFee memory _fee = _quote(
            READ_CHANNEL,
            _getCmd(app, callData),
            OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, uint32(returnDataSize * eids.length), 0),
            false
        );
        return _fee.nativeFee;
    }

    /**
     * @notice Processes and aggregates responses from LayerZero's read protocol
     * @param _cmd The encoded command from LayerZero
     * @param _responses Array of responses from each chain
     * @return The aggregated result from the callback contract
     */
    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external view returns (bytes memory) {
        // Decode the command using ReadCodecV1
        (uint16 _cmdLabel, EVMCallRequestV1[] memory _requests,) = ReadCodecV1.decode(_cmd);
        address app = getApp[_cmdLabel];
        if (app == address(0)) revert InvalidCmdLabel();
        if (_requests.length == 0) revert InvalidRequests();

        IGatewayApp.Request[] memory __requests = new IGatewayApp.Request[](_requests.length);
        for (uint256 i; i < _requests.length; i++) {
            EVMCallRequestV1 memory request = _requests[i];
            __requests[i] =
                IGatewayApp.Request(bytes32(uint256(request.targetEid)), request.blockNumOrTimestamp, request.to);
        }

        return IGatewayApp(app).reduce(__requests, _requests[0].callData, _responses);
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers an application with the gateway
     * @dev Assigns a unique command label to the app for LayerZero operations
     * @param app The application address to register
     */
    function registerApp(address app) external onlyOwner {
        uint16 cmdLabel = _lastCmdLabel + 1;
        _lastCmdLabel = cmdLabel;
        appStates[app].cmdLabel = cmdLabel;

        emit RegisterApp(app, cmdLabel);
    }

    /**
     * @notice Configures the chains and confirmation requirements for cross-chain operations
     * @dev Validates chain UIDs are within uint32 range and checks for duplicates
     * @param chainUIDs Array of chain unique identifiers to configure
     * @param confirmations Array of confirmation requirements for each chain
     */
    function configChains(bytes32[] memory chainUIDs, uint16[] memory confirmations) external onlyOwner {
        if (chainUIDs.length != confirmations.length) revert InvalidLengths();

        // Clear existing configuration mappings
        for (uint256 i; i < _targetEids.length; i++) {
            delete _chainConfigConfirmations[_targetEids[i]];
        }

        // Convert bytes32 chainUIDs to uint32 eids and validate
        uint32[] memory eids = new uint32[](chainUIDs.length);
        for (uint256 i; i < chainUIDs.length; i++) {
            if (uint256(chainUIDs[i]) >= type(uint32).max) revert InvalidChainUID();
            eids[i] = uint32(uint256(chainUIDs[i]));

            // Check for duplicates
            for (uint256 j = i + 1; j < chainUIDs.length; j++) {
                if (chainUIDs[i] == chainUIDs[j]) revert DuplicateTargetEid();
            }

            _chainConfigConfirmations[eids[i]] = confirmations[i];
        }

        _targetEids = eids;
    }

    /**
     * @notice Updates the cross-chain transfer delays for specified chain UIDs.
     * @dev Only callable by the contract owner.
     * @param chainUIDs An array of chain UIDs whose delays are to be updated.
     * @param delays An array of delay values corresponding to each chain UID.
     * @dev Both arrays must be of the same length.
     */
    function updateTransferDelays(bytes32[] memory chainUIDs, uint64[] memory delays) external onlyOwner {
        if (chainUIDs.length != delays.length) revert InvalidLengths();

        for (uint256 i; i < chainUIDs.length; ++i) {
            if (uint256(chainUIDs[i]) >= type(uint32).max) revert InvalidChainUID();
            uint32 eid = uint32(uint256(chainUIDs[i]));
            uint64 delay = delays[i];

            transferDelays[eid] = delay;

            emit UpdateTransferDelay(eid, delay);
        }
    }

    /**
     * @notice Updates the read target address for a specific chain
     * @param chainUID The chain unique identifier
     * @param target The target contract address on the remote chain
     * @dev Only callable by registered apps. Validates chainUID is within uint32 range.
     */
    function updateReadTarget(bytes32 chainUID, bytes32 target) external onlyApp {
        if (uint256(chainUID) >= type(uint32).max) revert InvalidChainUID();

        uint32 eid = uint32(uint256(chainUID));
        appStates[msg.sender].targets[eid] = target;

        emit UpdateReadTarget(msg.sender, eid, target);
    }

    /**
     * @notice Executes a cross-chain read operation
     * @param callData The function call data to execute on remote chains
     * @param extra Additional data for the operation
     * @param returnDataSize Expected size of return data per chain
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters
     * @return guid The unique identifier for this read operation
     */
    function read(bytes memory callData, bytes memory extra, uint32 returnDataSize, bytes memory data)
        external
        payable
        onlyApp
        returns (bytes32 guid)
    {
        if (data.length < 64) revert InvalidLzReadOptions();
        (uint128 gasLimit, address refundTo) = abi.decode(data, (uint128, address));
        (bytes32[] memory chainUIDs,) = chainConfigs();
        uint32[] memory eids = new uint32[](chainUIDs.length);
        for (uint256 i; i < chainUIDs.length; i++) {
            eids[i] = uint32(uint256(chainUIDs[i]));
        }
        // directly use endpoint.send() to bypass _payNative() check in _lzSend()
        MessagingReceipt memory receipt = endpoint.send{ value: msg.value }(
            MessagingParams(
                READ_CHANNEL,
                _getPeerOrRevert(READ_CHANNEL),
                _getCmd(msg.sender, callData),
                OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, uint32(returnDataSize * eids.length), 0),
                false
            ),
            payable(refundTo)
        );
        readRequests[receipt.guid] = ReadRequest(msg.sender, extra);
        return receipt.guid;
    }

    /**
     * @notice Quotes the messaging fee for sending a message to a specific chain
     * @param chainUID The destination chain unique identifier
     * @param app The application sending the message
     * @param message The message to send
     * @param gasLimit Gas limit for the operation
     * @return fee The estimated messaging fee
     */
    function quoteSendMessage(bytes32 chainUID, address app, bytes memory message, uint128 gasLimit)
        public
        view
        returns (uint256 fee)
    {
        if (uint256(chainUID) >= type(uint32).max) revert InvalidChainUID();
        uint32 eid = uint32(uint256(chainUID));
        address target = AddressCast.toAddress(appStates[app].targets[eid]);
        if (target == address(0)) revert InvalidTarget();
        MessagingFee memory _fee = _quote(
            eid, abi.encode(target, message), OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0), false
        );
        return _fee.nativeFee;
    }

    /**
     * @notice Sends a message to a specific chain
     * @param chainUID The destination chain unique identifier
     * @param message The message to send
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters
     * @return guid The unique identifier for this message
     */
    function sendMessage(bytes32 chainUID, bytes memory message, bytes memory data)
        external
        payable
        onlyApp
        returns (bytes32 guid)
    {
        if (uint256(chainUID) >= type(uint32).max) revert InvalidChainUID();
        uint32 eid = uint32(uint256(chainUID));
        address target = AddressCast.toAddress(appStates[msg.sender].targets[eid]);
        if (target == address(0)) revert InvalidTarget();
        (uint128 gasLimit, address refundTo) = abi.decode(data, (uint128, address));
        MessagingReceipt memory receipt = _lzSend(
            eid,
            abi.encode(target, message),
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0),
            MessagingFee(msg.value, 0),
            refundTo
        );

        emit MessageSent(eid, receipt.guid, message);
        return receipt.guid;
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal virtual override nonReentrant {
        if (_origin.srcEid == READ_CHANNEL) {
            // Handle read responses
            ReadRequest memory request = readRequests[_guid];
            if (request.app == address(0)) revert InvalidGuid();

            delete readRequests[_guid];

            IGatewayApp(request.app).onRead(_message, request.extra);
        } else {
            // Handle regular messages - forward to the target app
            // The message should contain the target app address
            uint32 eid = _origin.srcEid;
            (address target, bytes memory data) = abi.decode(_message, (address, bytes));

            // Forward to the target app
            IGatewayApp(target).onReceive(bytes32(uint256(eid)), data);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Generates LayerZero command for cross-chain read operation
     * @param app The application requesting the read
     * @param callData The function call data to execute on remote chains
     * @return The encoded LayerZero command
     * @dev Creates EVMCallRequestV1 structs for each configured chain with proper delays and confirmations
     */
    function _getCmd(address app, bytes memory callData) public view returns (bytes memory) {
        AppState storage state = appStates[app];
        if (state.cmdLabel == 0) revert InvalidApp();

        (bytes32[] memory _chainUIDs, uint16[] memory _confirmations) = chainConfigs();
        uint32[] memory _eids = new uint32[](_chainUIDs.length);
        for (uint256 i; i < _chainUIDs.length; i++) {
            _eids[i] = uint32(uint256(_chainUIDs[i]));
        }
        EVMCallRequestV1[] memory requests = new EVMCallRequestV1[](_eids.length);

        uint64 timestamp = uint64(block.timestamp);
        for (uint256 i; i < _eids.length; i++) {
            uint32 eid = _eids[i];
            address target = AddressCast.toAddress(state.targets[eid]);
            if (target == address(0)) revert InvalidTarget();
            requests[i] = EVMCallRequestV1({
                appRequestLabel: uint16(i + 1),
                targetEid: eid,
                isBlockNum: false,
                blockNumOrTimestamp: timestamp + transferDelays[eid],
                confirmations: _confirmations[i],
                to: target,
                callData: callData
            });
        }

        return ReadCodecV1.encode(state.cmdLabel, requests, _computeSettings());
    }

    /**
     * @notice Computes the LayerZero EVM call settings for read operations
     * @return EVMCallComputeV1 struct configured for lzReduce callback
     * @dev Always targets this gateway contract for response aggregation
     */
    function _computeSettings() internal view virtual returns (EVMCallComputeV1 memory) {
        return EVMCallComputeV1({
            computeSetting: 1, // lzReduce()
            targetEid: ILayerZeroEndpointV2(endpoint).eid(),
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 0,
            to: address(this) // Always target gateway for lzReduce
         });
    }
}
