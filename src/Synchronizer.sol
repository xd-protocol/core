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
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SynchronizerLocal, SynchronizerRemote } from "./mixins/SynchronizerRemote.sol";

contract Synchronizer is SynchronizerRemote, OAppRead {
    using OptionsBuilder for bytes;

    struct ChainConfig {
        uint32 targetEid;
        uint64 readDelay;
        uint16 confirmations;
        address to;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    uint32 public constant READ_CHANNEL = 4_294_967_295;
    uint16 public constant CMD_SYNC = 1;

    ChainConfig[] internal _chainConfigs;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event RequestSync(address indexed caller);
    event ReceiveRoot(uint32 indexed eid, bytes32 indexed liquidityRoot, bytes32 indexed dataRoot, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAddress();
    error DuplicateTargetEid();
    error InvalidCmd();

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _endpoint, address _owner) OAppRead(_endpoint, _owner) Ownable(_owner) {
        // Empty
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function chainConfigs() external view returns (ChainConfig[] memory) {
        return _chainConfigs;
    }

    /**
     * @notice Processes the responses from LayerZero's read protocol, aggregating results based on the command label.
     * @dev Currently only supports CMD_SYNC for syncing chain roots.
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
            return abi.encode(eids, liquidityRoots, dataRoots, timestamps);
        } else {
            revert InvalidCmd();
        }
    }

    /**
     * @notice Quotes the messaging fee for sending a read request with specific gas and calldata size.
     * @param _gas The amount of gas to allocate for the executor.
     * @param _calldataSize The size of the calldata in bytes.
     * @return fee The estimated messaging fee for the request.
     */
    function quote(uint128 _gas, uint32 _calldataSize) public view returns (MessagingFee memory fee) {
        bytes memory cmd = getCmd();
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReadOption(_gas, _calldataSize, 0);
        return _quote(READ_CHANNEL, cmd, options, false);
    }

    /**
     * @notice Constructs and encodes the read command for LayerZero's read protocol.
     * @dev Uses `_computeSettings` to determine the compute settings for the command.
     * @return The encoded command with all configured chain requests.
     */
    function getCmd() public view returns (bytes memory) {
        uint256 length = _chainConfigs.length;
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](length);

        uint64 timestamp = uint64(block.timestamp);
        for (uint256 i; i < length; i++) {
            ChainConfig memory chainConfig = _chainConfigs[i];
            readRequests[i] = EVMCallRequestV1({
                appRequestLabel: uint16(i + 1),
                targetEid: chainConfig.targetEid,
                isBlockNum: false,
                blockNumOrTimestamp: timestamp + chainConfig.readDelay,
                confirmations: chainConfig.confirmations,
                to: chainConfig.to,
                callData: abi.encodeWithSelector(SynchronizerLocal.getTopTreeRoots.selector)
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

    function _eidsLength() internal view override returns (uint256) {
        return _chainConfigs.length;
    }

    function _eidAt(uint256 index) internal view override returns (uint32) {
        return _chainConfigs[index].targetEid;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

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
     * @notice Initiates a sync operation using LayerZero's read protocol.
     * @dev Sends a read request with specified gas and calldata size.
     *      The user must provide sufficient fees via `msg.value`.
     * @param gasLimit The gas limit to allocate for the executor.
     * @param calldataSize The size of the calldata for the request, in bytes.
     * @return fee The messaging receipt from LayerZero, confirming the request details.
     *         Includes the `guid` and `block` parameters for tracking.
     */
    function sync(uint128 gasLimit, uint32 calldataSize) external payable returns (MessagingReceipt memory fee) {
        // TODO: check for redundant sync requests

        bytes memory cmd = getCmd();
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, calldataSize, 0);
        fee = _lzSend(READ_CHANNEL, cmd, options, MessagingFee(msg.value, 0), payable(msg.sender));

        emit RequestSync(msg.sender);
    }

    /**
     * @notice Handles messages received from LayerZero's messaging protocol.
     * @dev Updates the root and timestamp for each chain ID based on the received message.
     * @param _message The encoded payload containing chain roots and timestamps.
     */
    function _lzReceive(
        Origin calldata, /* _origin */
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal virtual override {
        (uint32[] memory eids, bytes32[] memory liquidityRoots, bytes32[] memory dataRoots, uint256[] memory timestamps)
        = abi.decode(_message, (uint32[], bytes32[], bytes32[], uint256[]));
        for (uint256 i; i < eids.length; ++i) {
            (uint32 eid, bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp) =
                (eids[i], liquidityRoots[i], dataRoots[i], timestamps[i]);
            if (timestamp <= lastRootTimestamp[eid]) continue;

            liquidityRoots[eid] = liquidityRoot;
            dataRoots[eid] = dataRoot;
            lastRootTimestamp[eid] = timestamp;

            emit ReceiveRoot(eid, liquidityRoot, dataRoot, timestamp);
        }
    }
}
