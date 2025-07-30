// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

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
    ILayerZeroEndpointV2
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ILiquidityMatrix } from "./interfaces/ILiquidityMatrix.sol";
import { ISynchronizer } from "./interfaces/ISynchronizer.sol";

/**
 * @title Synchronizer
 * @notice Implements LayerZero's read and messaging protocols to synchronize liquidity and data roots across multiple chains
 * @dev This contract handles all cross-chain communication for LiquidityMatrix.
 *      It is pluggable and can be replaced with other interoperability solutions.
 *
 * ## Architecture Overview:
 *
 * The Synchronizer acts as a bridge between LiquidityMatrix and LayerZero's cross-chain infrastructure:
 * - **OAppRead Integration**: Uses LayerZero's read protocol to fetch roots from multiple chains
 * - **Messaging Protocol**: Handles cross-chain account mapping requests
 * - **Rate Limiting**: Prevents spam by limiting sync operations to one per block
 * - **Configurable Chains**: Allows dynamic configuration of target chains and confirmations
 *
 * ## Sync Flow:
 *
 * 1. **Initiation**: Authorized syncer calls `sync()` with gas parameters
 * 2. **Read Request**: Sends read requests to all configured chains via LayerZero
 * 3. **Aggregation**: LayerZero aggregates responses using `lzReduce()` on the READ_CHANNEL
 * 4. **Receipt**: Aggregated roots are received via `_lzReceive()`
 * 5. **Storage**: Roots are forwarded to LiquidityMatrix for storage and settlement
 *
 * ## Account Mapping Flow:
 *
 * 1. **Request**: App calls `requestMapRemoteAccounts()` with account arrays
 * 2. **Cross-chain Message**: Request is sent to the remote chain via LayerZero
 * 3. **Remote Processing**: Remote chain receives and processes the mapping request
 * 4. **Validation**: Remote app validates mappings via `shouldMapAccounts()` callback
 * 5. **Storage**: Approved mappings are stored in LiquidityMatrix
 */
contract Synchronizer is OAppRead, ISynchronizer {
    using OptionsBuilder for bytes;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    // LayerZero read channel threshold for identifying read vs regular channels
    uint32 internal constant READ_CHANNEL_EID_THRESHOLD = 4_294_965_694;
    // Command identifiers for different message types
    uint16 internal constant CMD_SYNC = 1;
    uint16 internal constant MAP_REMOTE_ACCOUNTS = 1;

    // Immutable read channel endpoint ID for LayerZero OAppRead
    uint32 public immutable READ_CHANNEL;

    // Address authorized to initiate sync operations
    address public syncer;
    // Reference to the LiquidityMatrix contract for state updates
    ILiquidityMatrix public immutable liquidityMatrix;

    // Array of configured target endpoint IDs to sync with
    uint32[] internal _targetEids;
    // Confirmation requirements for each target endpoint
    mapping(uint32 => uint16) internal _chainConfigConfirmations;

    // Rate limiting: timestamp of last sync request
    uint256 internal _lastSyncRequestTimestamp;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Restricts function access to registered applications or LiquidityMatrix
     */
    modifier onlyAppOrMatrix() {
        if (msg.sender == address(liquidityMatrix)) {
            // Trust calls from LiquidityMatrix as it validates the app
            _;
        } else {
            // Direct calls must be from registered apps
            (bool registered,,,) = liquidityMatrix.getAppSetting(msg.sender);
            if (!registered) revert Forbidden();
            _;
        }
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the Synchronizer with LayerZero integration
     * @param _readChannel The LayerZero read channel endpoint ID
     * @param _endpoint The LayerZero endpoint address
     * @param _liquidityMatrix The LiquidityMatrix contract address
     * @param _syncer The authorized syncer address
     * @param _owner The contract owner address
     */
    constructor(uint32 _readChannel, address _endpoint, address _liquidityMatrix, address _syncer, address _owner)
        OAppRead(_endpoint, _owner)
        Ownable(_owner)
    {
        READ_CHANNEL = _readChannel;
        liquidityMatrix = ILiquidityMatrix(_liquidityMatrix);
        syncer = _syncer;

        // Set self as peer for the read channel to receive aggregated responses
        _setPeer(_readChannel, AddressCast.toBytes32(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the configured target chains and their confirmation requirements
     * @return eids Array of endpoint IDs configured for syncing
     * @return confirmations Array of block confirmation requirements for each endpoint
     */
    function chainConfigs() external view returns (uint32[] memory eids, uint16[] memory confirmations) {
        uint256 length = _targetEids.length;
        eids = _targetEids;
        confirmations = new uint16[](length);
        for (uint256 i; i < length; i++) {
            confirmations[i] = _chainConfigConfirmations[_targetEids[i]];
        }
    }

    /**
     * @notice Processes the responses from LayerZero's read protocol, aggregating results based on the command label.
     * @dev Called by LayerZero's OAppRead infrastructure to reduce multiple chain responses into a single result.
     *      This aggregation happens on the READ_CHANNEL before forwarding to the target chain.
     * @param _cmd The encoded command specifying the request details
     * @param _responses An array of responses corresponding to each read request
     * @return The aggregated result containing synced chain roots and timestamps
     */
    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external pure returns (bytes memory) {
        (uint16 appCmdLabel, EVMCallRequestV1[] memory requests,) = ReadCodecV1.decode(_cmd);
        if (appCmdLabel == CMD_SYNC) {
            uint32[] memory eids = new uint32[](requests.length);
            bytes32[] memory liquidityRoots = new bytes32[](requests.length);
            bytes32[] memory dataRoots = new bytes32[](requests.length);
            uint256[] memory timestamps = new uint256[](requests.length);
            for (uint256 i; i < eids.length; ++i) {
                eids[i] = requests[i].targetEid;
                (liquidityRoots[i], dataRoots[i], timestamps[i]) =
                    abi.decode(_responses[i], (bytes32, bytes32, uint256));
            }
            return abi.encode(CMD_SYNC, eids, liquidityRoots, dataRoots, timestamps);
        } else {
            revert InvalidCmd();
        }
    }

    /**
     * @notice Quotes the messaging fee for syncing all configured chains
     * @dev Uses LayerZero's quote mechanism to estimate cross-chain messaging costs
     * @param gasLimit The amount of gas to allocate for the executor
     * @param calldataSize The size of the calldata in bytes
     * @return fee The estimated messaging fee in native token
     */
    function quoteSync(uint128 gasLimit, uint32 calldataSize) public view returns (uint256 fee) {
        MessagingFee memory _fee = _quote(
            READ_CHANNEL,
            getSyncCmd(),
            OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, calldataSize, 0),
            false
        );
        return _fee.nativeFee;
    }

    /**
     * @notice Quotes the messaging fee for sending a read request to specific endpoints.
     * @param eids Array of endpoint IDs to synchronize.
     * @param gasLimit The amount of gas to allocate for the executor.
     * @param calldataSize The size of the calldata in bytes.
     * @return fee The estimated messaging fee for the request.
     */
    function quoteSync(uint32[] memory eids, uint128 gasLimit, uint32 calldataSize) public view returns (uint256 fee) {
        MessagingFee memory _fee = _quote(
            READ_CHANNEL,
            getSyncCmd(eids),
            OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, calldataSize, 0),
            false
        );
        return _fee.nativeFee;
    }

    /**
     * @notice Quotes the messaging fee for requesting remote account mapping
     * @param eid The endpoint ID of the target chain
     * @param app The address of the local application
     * @param remoteApp The address of the remote application
     * @param locals Array of local account addresses
     * @param remotes Array of remote account addresses
     * @param gasLimit The gas limit for the operation
     * @return fee The estimated messaging fee in native token
     */
    function quoteRequestMapRemoteAccounts(
        uint32 eid,
        address app,
        address remoteApp,
        address[] memory locals,
        address[] memory remotes,
        uint128 gasLimit
    ) public view returns (uint256 fee) {
        MessagingFee memory _fee = _quote(
            eid,
            abi.encode(MAP_REMOTE_ACCOUNTS, app, remoteApp, locals, remotes),
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0),
            false
        );
        return _fee.nativeFee;
    }

    /**
     * @notice Constructs and encodes the read command for all configured chains
     * @dev Creates EVMCallRequestV1 structures for each target chain to fetch their main roots.
     *      Uses current block timestamp for consistency across chains.
     * @return The encoded command with all configured chain requests
     */
    function getSyncCmd() public view returns (bytes memory) {
        uint256 length = _targetEids.length;
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](length);

        uint64 timestamp = uint64(block.timestamp);
        for (uint256 i; i < length; i++) {
            uint32 eid = _targetEids[i];
            address to = AddressCast.toAddress(_getPeerOrRevert(eid));
            uint16 confirmations = _chainConfigConfirmations[eid];
            // Build read request for this endpoint
            readRequests[i] = EVMCallRequestV1({
                appRequestLabel: uint16(i + 1),
                targetEid: eid,
                isBlockNum: false,
                blockNumOrTimestamp: timestamp,
                confirmations: confirmations,
                to: to,
                callData: abi.encodeWithSelector(ILiquidityMatrix.getMainRoots.selector)
            });
        }

        return ReadCodecV1.encode(CMD_SYNC, readRequests, _computeSettings());
    }

    /**
     * @notice Constructs and encodes the read command for specific chains.
     * @dev Uses `_computeSettings` to determine the compute settings for the command.
     *      Only includes the specified endpoint IDs in the sync request.
     * @param eids Array of endpoint IDs to include in the sync command.
     * @return The encoded command with the specified chain requests.
     */
    function getSyncCmd(uint32[] memory eids) public view returns (bytes memory) {
        uint256 length = eids.length;
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](length);

        uint64 timestamp = uint64(block.timestamp);
        for (uint256 i; i < length; i++) {
            uint32 eid = eids[i];
            address to = AddressCast.toAddress(_getPeerOrRevert(eid));
            uint16 confirmations = _chainConfigConfirmations[eid];

            // Build read request for this endpoint
            readRequests[i] = EVMCallRequestV1({
                appRequestLabel: uint16(i + 1),
                targetEid: eid,
                isBlockNum: false,
                blockNumOrTimestamp: timestamp,
                confirmations: confirmations,
                to: to,
                callData: abi.encodeWithSelector(ILiquidityMatrix.getMainRoots.selector)
            });
        }

        return ReadCodecV1.encode(CMD_SYNC, readRequests, _computeSettings());
    }

    /**
     * @notice Computes the settings for LayerZero read aggregation
     * @dev Configures the compute settings to use lzReduce() for response aggregation
     * @return Compute settings specifying where and how to process responses
     */
    function _computeSettings() internal view returns (EVMCallComputeV1 memory) {
        return EVMCallComputeV1({
            computeSetting: 1, // lzReduce()
            targetEid: ILayerZeroEndpointV2(endpoint).eid(),
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 0,
            to: address(this)
        });
    }

    /**
     * @notice Returns the number of configured target endpoint IDs
     * @dev Used by LiquidityMatrix to iterate through all configured chains
     * @return The length of the target endpoints array
     */
    function eidsLength() public view override returns (uint256) {
        return _targetEids.length;
    }

    /**
     * @notice Returns the endpoint ID at the specified index
     * @dev Used by LiquidityMatrix to access specific endpoint IDs during iteration
     * @param index The index in the target endpoints array
     * @return The endpoint ID at the given index
     */
    function eidAt(uint256 index) public view override returns (uint32) {
        return _targetEids[index];
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the configuration for target chains used in LayerZero read requests
     * @dev Clears existing configuration and sets new target chains with their confirmation requirements.
     *      Validates for duplicate endpoint IDs to prevent configuration errors.
     * @param eids Array of endpoint IDs to sync with
     * @param confirmations Array of confirmation requirements for each endpoint
     */
    function configChains(uint32[] memory eids, uint16[] memory confirmations) external onlyOwner {
        if (eids.length != confirmations.length) revert InvalidLengths();

        // Clear existing configuration mappings
        for (uint256 i; i < _targetEids.length; i++) {
            delete _chainConfigConfirmations[_targetEids[i]];
        }

        // Validate for duplicates and populate new configuration
        for (uint256 i; i < eids.length; i++) {
            for (uint256 j = i + 1; j < eids.length; j++) {
                if (eids[i] == eids[j]) revert DuplicateTargetEid();
            }
            _chainConfigConfirmations[eids[i]] = confirmations[i];
        }

        _targetEids = eids;
    }

    /**
     * @notice Updates the authorized syncer address
     * @dev Only the syncer can initiate cross-chain sync operations
     * @param _syncer New syncer address
     */
    function updateSyncer(address _syncer) external onlyOwner {
        syncer = _syncer;

        emit UpdateSyncer(_syncer);
    }

    /**
     * @notice Initiates a sync operation for all configured chains using lzRead
     * @dev Sends a cross-chain read request to fetch main roots from all target chains.
     *      Enforces rate limiting to prevent spam (one request per block).
     *      The syncer must provide sufficient fees via `msg.value`.
     * @param gasLimit The gas limit to allocate for the executor
     * @param calldataSize The size of the calldata for the request, in bytes
     * @return receipt The messaging receipt from LayerZero, includes guid and block for tracking
     */
    function sync(uint128 gasLimit, uint32 calldataSize) external payable returns (MessagingReceipt memory receipt) {
        // Verify caller is authorized syncer
        if (msg.sender != syncer) revert Forbidden();
        // Rate limiting: only one sync per block
        if (block.timestamp <= _lastSyncRequestTimestamp) revert AlreadyRequested();
        _lastSyncRequestTimestamp = block.timestamp;

        bytes memory cmd = getSyncCmd();
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, calldataSize, 0);
        receipt = _lzSend(READ_CHANNEL, cmd, options, MessagingFee(msg.value, 0), payable(msg.sender));

        emit Sync(msg.sender);
    }

    /**
     * @notice Initiates a sync operation for specific chains using lzRead.
     * @dev Sends a read request for the specified endpoint IDs with gas and calldata size.
     *      The user must provide sufficient fees via `msg.value`.
     * @param eids Array of endpoint IDs to synchronize.
     * @param gasLimit The gas limit to allocate for the executor.
     * @param calldataSize The size of the calldata for the request, in bytes.
     * @return receipt The messaging receipt from LayerZero, confirming the request details.
     *         Includes the `guid` and `block` parameters for tracking.
     */
    function sync(uint32[] memory eids, uint128 gasLimit, uint32 calldataSize)
        external
        payable
        returns (MessagingReceipt memory receipt)
    {
        // Verify caller is authorized syncer
        if (msg.sender != syncer) revert Forbidden();
        // Rate limiting: only one sync per block
        if (block.timestamp <= _lastSyncRequestTimestamp) revert AlreadyRequested();
        _lastSyncRequestTimestamp = block.timestamp;

        bytes memory cmd = getSyncCmd(eids);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, calldataSize, 0);
        receipt = _lzSend(READ_CHANNEL, cmd, options, MessagingFee(msg.value, 0), payable(msg.sender));

        emit Sync(msg.sender);
    }

    /**
     * @notice Requests mapping of remote accounts to local accounts on another chain
     * @dev Sends a cross-chain message to map accounts between chains.
     *      Validates address arrays have matching lengths and no zero addresses.
     * @param eid Target chain endpoint ID
     * @param remoteApp Address of the app on the remote chain
     * @param locals Array of local account addresses to map
     * @param remotes Array of remote account addresses to map
     * @param gasLimit Gas limit for the cross-chain message execution
     */
    function requestMapRemoteAccounts(
        uint32 eid,
        address remoteApp,
        address[] memory locals,
        address[] memory remotes,
        uint128 gasLimit
    ) external payable onlyAppOrMatrix {
        // Validate input arrays
        if (remotes.length != locals.length) revert InvalidLengths();
        for (uint256 i; i < locals.length; ++i) {
            (address local, address remote) = (locals[i], remotes[i]);
            if (local == address(0) || remote == address(0)) revert InvalidAddress();
        }

        // Send cross-chain message to map accounts
        _lzSend(
            eid,
            abi.encode(MAP_REMOTE_ACCOUNTS, msg.sender, remoteApp, locals, remotes),
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0),
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
        emit RequestMapRemoteAccounts(msg.sender, eid, remoteApp, remotes, locals);
    }

    /**
     * @notice Handles messages received from LayerZero's messaging protocol
     * @dev Processes two types of messages:
     *      1. Sync responses from READ_CHANNEL containing aggregated roots
     *      2. Account mapping requests from other chains
     * @param _origin Origin information including source endpoint ID
     * @param _message The encoded payload containing message type and data
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal virtual override {
        if (_origin.srcEid == READ_CHANNEL) {
            // Handle aggregated sync response from read channel
            (
                ,
                uint32[] memory eids,
                bytes32[] memory liquidityRoots,
                bytes32[] memory dataRoots,
                uint256[] memory timestamps
            ) = abi.decode(_message, (uint16, uint32[], bytes32[], bytes32[], uint256[]));
            // Forward each chain's roots to LiquidityMatrix
            for (uint256 i; i < eids.length; ++i) {
                liquidityMatrix.onReceiveRoots(eids[i], liquidityRoots[i], dataRoots[i], timestamps[i]);
            }
        } else {
            // Handle direct messages from other chains
            uint16 msgType = abi.decode(_message, (uint16));
            if (msgType == MAP_REMOTE_ACCOUNTS) {
                // Process account mapping request
                uint32 eid = _origin.srcEid;
                (,, address toApp, address[] memory remotes, address[] memory locals) =
                    abi.decode(_message, (uint16, address, address, address[], address[]));

                // Forward to LiquidityMatrix for processing
                // Pass toApp (the local app) as fromApp parameter - this is the app that should process the request
                // The actual fromApp is not needed as we can verify the mapping through toApp's remote state
                liquidityMatrix.onReceiveMapRemoteAccountRequests(eid, toApp, abi.encode(remotes, locals));
            } else {
                revert InvalidMsgType();
            }
        }
    }
}
