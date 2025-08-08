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
    mapping(bytes32 guid => ReadRequest) public requests;

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
    error InvalidChainIdentifier();
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

    function chainConfigs() public view returns (uint32[] memory eids, uint16[] memory confirmations) {
        uint256 length = _targetEids.length;
        eids = _targetEids;
        confirmations = new uint16[](length);
        for (uint256 i; i < length; i++) {
            confirmations[i] = _chainConfigConfirmations[_targetEids[i]];
        }
    }

    function eidsLength() public view returns (uint256) {
        return _targetEids.length;
    }

    function eidAt(uint256 index) public view returns (uint32) {
        return _targetEids[index];
    }

    /**
     * @notice Quotes the messaging fee for sending a read request with specific calldata.
     * @param gasLimit The gas limit to allocate for actual transfer after lzRead.
     * @return fee The estimated messaging fee for the request.
     */
    function quoteRead(address app, bytes memory callData, uint32 returnDataSize, uint128 gasLimit)
        public
        view
        returns (uint256 fee)
    {
        (uint32[] memory eids,) = chainConfigs();
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

    function registerApp(address app) external onlyOwner {
        uint16 cmdLabel = _lastCmdLabel + 1;
        _lastCmdLabel = cmdLabel;
        appStates[app].cmdLabel = cmdLabel;

        emit RegisterApp(app, cmdLabel);
    }

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

    function updateReadTarget(bytes32 chainIdentifier, bytes32 target) external onlyApp {
        if (uint256(chainIdentifier) >= type(uint32).max) revert InvalidChainIdentifier();

        uint32 eid = uint32(uint256(chainIdentifier));
        appStates[msg.sender].targets[eid] = target;

        emit UpdateReadTarget(msg.sender, eid, target);
    }

    function read(bytes memory callData, bytes memory extra, uint32 returnDataSize, bytes memory data)
        external
        payable
        onlyApp
        returns (bytes32 guid)
    {
        if (data.length < 64) revert InvalidLzReadOptions();
        (uint128 gasLimit, address refundTo) = abi.decode(data, (uint128, address));
        (uint32[] memory eids,) = chainConfigs();
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
        requests[receipt.guid] = ReadRequest(msg.sender, extra);
        return receipt.guid;
    }

    function quoteSendMessage(uint32 eid, address app, bytes memory message, uint128 gasLimit)
        public
        view
        returns (uint256 fee)
    {
        address target = AddressCast.toAddress(appStates[app].targets[eid]);
        if (target == address(0)) revert InvalidTarget();
        MessagingFee memory _fee = _quote(
            eid, abi.encode(target, message), OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0), false
        );
        return _fee.nativeFee;
    }

    function sendMessage(uint32 eid, bytes memory message, bytes memory data)
        external
        payable
        onlyApp
        returns (bytes32 guid)
    {
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
            ReadRequest memory request = requests[_guid];
            if (request.app == address(0)) revert InvalidGuid();

            delete requests[_guid];

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

    function _getCmd(address app, bytes memory callData) public view returns (bytes memory) {
        AppState storage state = appStates[app];
        if (state.cmdLabel == 0) revert InvalidApp();

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
