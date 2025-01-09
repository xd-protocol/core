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
import { SynchronizerLocal } from "./mixins/SynchronizerLocal.sol";
import { SynchronizerRemoteBatched } from "./mixins/SynchronizerRemoteBatched.sol";
import { SnapshotsLib } from "./libraries/SnapshotsLib.sol";

/**
 * @title Synchronizer
 * @dev Extends SynchronizerRemoteBatched and integrates LayerZero's read and messaging protocols
 *      to synchronize liquidity and data roots across multiple chains. This contract provides:
 *      - Chain configuration for read requests.
 *      - Messaging-based remote application and account updates.
 */
contract Synchronizer is SynchronizerRemoteBatched, OAppRead {
    using OptionsBuilder for bytes;
    using SnapshotsLib for SnapshotsLib.Snapshots;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    uint32 constant READ_CHANNEL_EID_THRESHOLD = 4_294_965_694;
    uint16 public constant CMD_SYNC = 1;
    uint16 public constant MAP_REMOTE_ACCOUNTS = 1;

    uint32 public immutable READ_CHANNEL;

    ChainConfig[] internal _chainConfigs;

    uint256 internal _lastSyncRequestTimestamp;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Sync(address indexed caller);
    event RequestMapRemoteAccounts(
        address indexed app, uint32 indexed eid, address indexed remoteApp, address[] locals, address[] remotes
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAddress();
    error DuplicateTargetEid();
    error InvalidCmd();
    error AlreadyRequested();
    error InvalidMsgType();
    error InvalidMessage();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(uint32 _readChannel, address _endpoint, address _owner) OAppRead(_endpoint, _owner) Ownable(_owner) {
        READ_CHANNEL = _readChannel;

        _setPeer(_readChannel, AddressCast.toBytes32(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function chainConfigs() external view returns (ChainConfig[] memory) {
        return _chainConfigs;
    }

    /**
     * @notice Processes the responses from LayerZero's read protocol, aggregating results based on the command label.
     * @param _cmd The encoded command specifying the request details.
     * @param _responses An array of responses corresponding to each read request.
     * @return The aggregated result, such as synced chain roots and timestamps.
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
     * @notice Quotes the messaging fee for sending a read request with specific gas and calldata size.
     * @param gasLimit The amount of gas to allocate for the executor.
     * @param calldataSize The size of the calldata in bytes.
     * @return fee The estimated messaging fee for the request.
     */
    function quoteSync(uint128 gasLimit, uint32 calldataSize) public view returns (MessagingFee memory fee) {
        return _quote(
            READ_CHANNEL,
            getSyncCmd(),
            OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, calldataSize, 0),
            false
        );
    }

    /**
     * @notice Quotes the messaging fee for sending a write request with specific gas and calldata size.
     * @param gasLimit The amount of gas to allocate for the executor.
     * @return fee The estimated messaging fee for the request.
     */
    function quoteRequestMapRemoteAccounts(
        uint32 eid,
        address app,
        address remoteApp,
        address[] memory locals,
        address[] memory remotes,
        uint128 gasLimit
    ) public view returns (MessagingFee memory fee) {
        return _quote(
            eid,
            abi.encode(MAP_REMOTE_ACCOUNTS, app, remoteApp, locals, remotes),
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0),
            false
        );
    }

    /**
     * @notice Constructs and encodes the read command for LayerZero's read protocol.
     * @dev Uses `_computeSettings` to determine the compute settings for the command.
     * @return The encoded command with all configured chain requests.
     */
    function getSyncCmd() public view returns (bytes memory) {
        uint256 length = _chainConfigs.length;
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](length);

        uint64 timestamp = uint64(block.timestamp);
        for (uint256 i; i < length; i++) {
            ChainConfig memory chainConfig = _chainConfigs[i];
            readRequests[i] = EVMCallRequestV1({
                appRequestLabel: uint16(i + 1),
                targetEid: chainConfig.targetEid,
                isBlockNum: false,
                blockNumOrTimestamp: timestamp,
                confirmations: chainConfig.confirmations,
                to: chainConfig.to,
                callData: abi.encodeWithSelector(SynchronizerLocal.getMainRoots.selector)
            });
        }

        return ReadCodecV1.encode(CMD_SYNC, readRequests, _computeSettings());
    }

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

    function eidsLength() public view override returns (uint256) {
        return _chainConfigs.length;
    }

    function eidAt(uint256 index) public view override returns (uint32) {
        return _chainConfigs[index].targetEid;
    }

    /**
     * @notice Updates the configuration for target chains used in LayerZero read requests.
     * @param configs An array of new `ChainConfig` objects defining the target chains.
     */
    function configChains(ChainConfig[] memory configs) external onlyOwner {
        for (uint256 i; i < configs.length; i++) {
            if (configs[i].to == address(0)) revert InvalidAddress();

            for (uint256 j = i + 1; j < configs.length; j++) {
                if (configs[i].targetEid == configs[j].targetEid) revert DuplicateTargetEid();
            }
        }

        _chainConfigs = configs;
    }

    /**
     * @notice Initiates a sync operation using lzRead.
     * @dev Sends a read request with specified gas and calldata size.
     *      The user must provide sufficient fees via `msg.value`.
     * @param gasLimit The gas limit to allocate for the executor.
     * @param calldataSize The size of the calldata for the request, in bytes.
     * @return fee The messaging receipt from LayerZero, confirming the request details.
     *         Includes the `guid` and `block` parameters for tracking.
     */
    function sync(uint128 gasLimit, uint32 calldataSize) external payable returns (MessagingReceipt memory fee) {
        if (block.timestamp <= _lastSyncRequestTimestamp) revert AlreadyRequested();
        _lastSyncRequestTimestamp = block.timestamp;

        bytes memory cmd = getSyncCmd();
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, calldataSize, 0);
        fee = _lzSend(READ_CHANNEL, cmd, options, MessagingFee(msg.value, 0), payable(msg.sender));

        emit Sync(msg.sender);
    }

    function requestMapRemoteAccounts(
        uint32 eid,
        address remoteApp,
        address[] memory locals,
        address[] memory remotes,
        uint128 gasLimit
    ) external payable onlyApp(msg.sender) {
        if (remotes.length != locals.length) revert InvalidLengths();
        for (uint256 i; i < locals.length; ++i) {
            (address local, address remote) = (locals[i], remotes[i]);
            if (local == address(0) || remote == address(0)) revert InvalidAddress();
        }

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
     * @notice Handles messages received from LayerZero's messaging protocol.
     * @dev Updates the root and timestamp for each chain ID based on the received message.
     * @param _message The encoded payload containing chain roots and timestamps.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal virtual override {
        if (_origin.srcEid == READ_CHANNEL) {
            (
                ,
                uint32[] memory eids,
                bytes32[] memory liquidityRoots,
                bytes32[] memory dataRoots,
                uint256[] memory timestamps
            ) = abi.decode(_message, (uint16, uint32[], bytes32[], bytes32[], uint256[]));
            for (uint256 i; i < eids.length; ++i) {
                _onReceiveRoots(eids[i], liquidityRoots[i], dataRoots[i], timestamps[i]);
            }
        } else {
            uint16 msgType = abi.decode(_message, (uint16));
            if (msgType == MAP_REMOTE_ACCOUNTS) {
                uint32 eid = _origin.srcEid;
                (, address remoteApp, address app, address[] memory remotes, address[] memory locals) =
                    abi.decode(_message, (uint16, address, address, address[], address[]));
                if (_remoteStates[app][eid].app != remoteApp) revert Forbidden();

                _mapRemoteAccounts(app, eid, remotes, locals);
            } else {
                revert InvalidMsgType();
            }
        }
    }
}
