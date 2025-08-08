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
    MessagingParams,
    ILayerZeroEndpointV2
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { IGateway } from "../interfaces/IGateway.sol";
import { IGatewayReader } from "../interfaces/IGatewayReader.sol";
import { ILiquidityMatrix } from "../interfaces/ILiquidityMatrix.sol";
import { ISynchronizer } from "../interfaces/ISynchronizer.sol";

contract LayerZeroGateway is OAppRead, ReentrancyGuard, IGateway {
    using OptionsBuilder for bytes;

    struct ReaderState {
        uint16 cmdLabel;
        mapping(uint32 eid => bytes32) targets;
    }

    struct ReadRequest {
        address reader;
        bytes extra;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint32 public immutable READ_CHANNEL;
    address public immutable liquidityMatrix;

    uint32 public transferCalldataSize = 32;

    mapping(address app => ReaderState) public readerStates;
    mapping(uint16 cmdLabel => address app) public getReader;
    mapping(uint32 eid => uint64) public transferDelays;

    uint16 internal _lastCmdLabel;
    mapping(bytes32 guid => ReadRequest) public requests;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterReader(address indexed app, uint16 indexed cmdLabel);
    event UpdateTransferDelay(uint32 indexed eid, uint64 delay);
    event UpdateTransferCalldataSize(uint128 size);
    event UpdateReadTarget(address indexed app, uint32 indexed eid, bytes32 indexed target);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Forbidden();
    error InvalidReader();
    error InvalidTarget();
    error InvalidLengths();
    error InvalidChainIdentifier();
    error InvalidLzReadOptions();
    error InvalidGuid();
    error InvalidCmdLabel();
    error InvalidRequests();

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyReader() {
        if (readerStates[msg.sender].cmdLabel == 0) revert Forbidden();
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

    function chainConfigs() public view returns (uint32[] memory eids, uint16[] memory confirmations) {
        address synchronizer = ILiquidityMatrix(liquidityMatrix).synchronizer();
        return ISynchronizer(synchronizer).chainConfigs();
    }

    /**
     * @notice Quotes the messaging fee for sending a read request with specific calldata.
     * @param gasLimit The gas limit to allocate for actual transfer after lzRead.
     * @return fee The estimated messaging fee for the request.
     */
    function quoteRead(address app, bytes memory callData, uint128 gasLimit) public view returns (uint256 fee) {
        (uint32[] memory eids,) = chainConfigs();
        MessagingFee memory _fee = _quote(
            READ_CHANNEL,
            _getCmd(app, callData),
            OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, uint32(transferCalldataSize * eids.length), 0),
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
        address app = getReader[_cmdLabel];
        if (app == address(0)) revert InvalidCmdLabel();
        if (_requests.length == 0) revert InvalidRequests();

        IGatewayReader.Request[] memory __requests = new IGatewayReader.Request[](_requests.length);
        for (uint256 i; i < _requests.length; i++) {
            EVMCallRequestV1 memory request = _requests[i];
            __requests[i] =
                IGatewayReader.Request(bytes32(uint256(request.targetEid)), request.blockNumOrTimestamp, request.to);
        }

        return IGatewayReader(app).reduce(__requests, _requests[0].callData, _responses);
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function registerReader(address app) external onlyOwner {
        uint16 cmdLabel = _lastCmdLabel + 1;
        _lastCmdLabel = cmdLabel;
        readerStates[app].cmdLabel = cmdLabel;

        emit RegisterReader(app, cmdLabel);
    }

    /**
     * @notice Updates the cross-chain transfer delays for specified endpoint IDs.
     * @dev Only callable by the contract owner.
     * @param eids An array of endpoint IDs whose delays are to be updated.
     * @param delays An array of delay values corresponding to each endpoint ID.
     * @dev Both arrays must be of the same length.
     */
    function updateTransferDelays(uint32[] memory eids, uint64[] memory delays) external onlyOwner {
        if (eids.length != delays.length) revert InvalidLengths();

        for (uint256 i; i < eids.length; ++i) {
            uint32 eid = eids[i];
            uint64 delay = delays[i];

            transferDelays[eid] = delay;

            emit UpdateTransferDelay(eid, delay);
        }
    }

    function updateTransferCalldataSize(uint32 size) external onlyOwner {
        transferCalldataSize = size;

        emit UpdateTransferCalldataSize(size);
    }

    function updateReadTarget(bytes32 chainIdentifier, bytes32 target) external onlyReader {
        if (uint256(chainIdentifier) >= type(uint32).max) revert InvalidChainIdentifier();

        uint32 eid = uint32(uint256(chainIdentifier));
        readerStates[msg.sender].targets[eid] = target;

        emit UpdateReadTarget(msg.sender, eid, target);
    }

    function read(bytes memory callData, bytes memory extra, bytes memory data)
        external
        payable
        onlyReader
        returns (bytes32 guid)
    {
        // directly use endpoint.send() to bypass _payNative() check in _lzSend()
        if (data.length < 64) revert InvalidLzReadOptions();
        (uint128 gasLimit, address refundTo) = abi.decode(data, (uint128, address));
        (uint32[] memory eids,) = chainConfigs();
        MessagingReceipt memory receipt = endpoint.send{ value: msg.value }(
            MessagingParams(
                READ_CHANNEL,
                _getPeerOrRevert(READ_CHANNEL),
                _getCmd(msg.sender, callData),
                OptionsBuilder.newOptions().addExecutorLzReadOption(
                    gasLimit, transferCalldataSize * uint32(eids.length), 0
                ),
                false
            ),
            payable(refundTo)
        );
        requests[receipt.guid] = ReadRequest(msg.sender, extra);
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
            ReadRequest memory request = requests[_guid];
            if (request.reader == address(0)) revert InvalidGuid();

            delete requests[_guid];

            IGatewayReader(request.reader).onRead(_message, request.extra);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getCmd(address app, bytes memory callData) public view returns (bytes memory) {
        ReaderState storage state = readerStates[app];
        if (state.cmdLabel == 0) revert InvalidReader();

        (uint32[] memory _eids, uint16[] memory _confirmations) = chainConfigs();
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](_eids.length);

        uint64 timestamp = uint64(block.timestamp);
        for (uint256 i; i < _eids.length; i++) {
            uint32 eid = _eids[i];
            address target = AddressCast.toAddress(state.targets[eid]);
            if (target == address(0)) revert InvalidTarget();
            readRequests[i] = EVMCallRequestV1({
                appRequestLabel: uint16(i + 1),
                targetEid: eid,
                isBlockNum: false,
                blockNumOrTimestamp: timestamp + transferDelays[eid],
                confirmations: _confirmations[i],
                to: target,
                callData: callData
            });
        }

        return ReadCodecV1.encode(state.cmdLabel, readRequests, _computeSettings());
    }

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
