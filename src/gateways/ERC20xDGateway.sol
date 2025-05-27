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
import { IERC20xDGateway } from "../interfaces/IERC20xDGateway.sol";
import { IERC20xDGatewayCallbacks } from "../interfaces/IERC20xDGatewayCallbacks.sol";
import { ILiquidityMatrix } from "../interfaces/ILiquidityMatrix.sol";
import { AddressLib } from "../libraries/AddressLib.sol";
import { LzLib } from "../libraries/LzLib.sol";

contract ERC20xDGateway is OAppRead, ReentrancyGuard, IERC20xDGateway {
    using OptionsBuilder for bytes;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint32 public immutable READ_CHANNEL;
    address public immutable liquidityMatrix;

    uint32 public transferCalldataSize = 32;

    mapping(uint32 eid => uint64) internal _transferDelays;
    mapping(bytes32 guid => address) internal _readers;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateTransferDelay(uint32 indexed eid, uint64 delay);
    event UpdateTransferCalldataSize(uint128 size);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidLengths();
    error InvalidGuid();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ERC20xDGateway contract with the necessary configurations.
     * @param _owner The address that will be granted ownership privileges.
     */
    constructor(uint32 _readChannel, address _liquidityMatrix, address _owner)
        OAppRead(address(ILiquidityMatrix(_liquidityMatrix).endpoint()), _owner)
        Ownable(_owner)
    {
        READ_CHANNEL = _readChannel;
        liquidityMatrix = _liquidityMatrix;

        _setPeer(READ_CHANNEL, AddressCast.toBytes32(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function chainConfigs() public view returns (ILiquidityMatrix.ChainConfig[] memory) {
        return ILiquidityMatrix(liquidityMatrix).chainConfigs();
    }

    function transferDelay(uint32 eid) external view returns (uint256) {
        return _transferDelays[eid];
    }

    /**
     * @notice Quotes the messaging fee for sending a read request with specific calldata.
     * @param gasLimit The gas limit to allocate for actual transfer after lzRead.
     * @return fee The estimated messaging fee for the request.
     */
    function quoteRead(bytes memory cmd, uint128 gasLimit) public view returns (uint256 fee) {
        MessagingFee memory _fee = _quote(
            READ_CHANNEL,
            cmd,
            OptionsBuilder.newOptions().addExecutorLzReadOption(
                gasLimit, uint32(transferCalldataSize * chainConfigs().length), 0
            ),
            false
        );
        return _fee.nativeFee;
    }

    /**
     * @notice Constructs the command payload for initiating a cross-chain transfer read request.
     * @return cmd The encoded command data.
     * @dev Constructs read requests for each configured chain in the LiquidityMatrix.
     */
    function getCmd(uint16 cmdLabel, address[] memory targets, bytes memory callData)
        public
        view
        returns (bytes memory)
    {
        ILiquidityMatrix.ChainConfig[] memory _chainConfigs = chainConfigs();
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](_chainConfigs.length);

        uint64 timestamp = uint64(block.timestamp);
        for (uint256 i; i < _chainConfigs.length; i++) {
            ILiquidityMatrix.ChainConfig memory chainConfig = _chainConfigs[i];
            uint32 eid = chainConfig.targetEid;
            readRequests[i] = EVMCallRequestV1({
                appRequestLabel: uint16(i + 1),
                targetEid: eid,
                isBlockNum: false,
                blockNumOrTimestamp: timestamp + _transferDelays[eid],
                confirmations: chainConfig.confirmations,
                to: targets[i],
                callData: callData
            });
        }

        return ReadCodecV1.encode(cmdLabel, readRequests, _computeSettings(msg.sender));
    }

    function _computeSettings(address to) internal view virtual returns (EVMCallComputeV1 memory) {
        return EVMCallComputeV1({
            computeSetting: 1, // lzReduce()
            targetEid: ILayerZeroEndpointV2(endpoint).eid(),
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 0,
            to: to
        });
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

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

            _transferDelays[eid] = delay;

            emit UpdateTransferDelay(eid, delay);
        }
    }

    function updateTransferCalldataSize(uint32 size) external onlyOwner {
        transferCalldataSize = size;

        emit UpdateTransferCalldataSize(size);
    }

    function read(bytes memory cmd, bytes memory options) external payable returns (MessagingReceipt memory receipt) {
        // directly use endpoint.send() to bypass _payNative() check in _lzSend()
        (uint128 gasLimit, address refundTo) = LzLib.decodeOptions(options);
        receipt = endpoint.send{ value: msg.value }(
            MessagingParams(
                READ_CHANNEL,
                _getPeerOrRevert(READ_CHANNEL),
                cmd,
                OptionsBuilder.newOptions().addExecutorLzReadOption(
                    gasLimit, transferCalldataSize * uint32(chainConfigs().length), 0
                ),
                false
            ),
            payable(refundTo)
        );
        _readers[receipt.guid] = msg.sender;
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal virtual override nonReentrant {
        if (_origin.srcEid == READ_CHANNEL) {
            address to = _readers[_guid];
            if (to == address(0)) revert InvalidGuid();

            IERC20xDGatewayCallbacks(to).onRead(_message);
        }
    }
}
