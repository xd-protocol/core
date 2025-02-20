// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Owned } from "solmate/auth/Owned.sol";
import { ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ILayerZeroComposer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { IStargate, StargateLib } from "../libraries/StargateLib.sol";

abstract contract BaseStargateStaker is Owned, ILayerZeroComposer {
    using StargateLib for IStargate;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable endpoint;
    address public immutable stargate;

    mapping(uint32 srcEid => bool) public nativeEnabled;
    mapping(uint32 srcEid => mapping(address srcAsset => address)) public assets;

    mapping(bytes32 guid => bytes32 messageHash) public failedMessages;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateNativeEnabled(uint32 indexed srcEid, bool enabled);
    event UpdateAsset(uint32 indexed srcEid, address indexed srcAsset, address indexed asset);
    event LzCompose();
    event LzComposeFail(bytes32 indexed guid, bytes message, bytes reason);

    event Stake(uint32 indexed srcEid, address indexed srcAsset, address indexed asset, uint256 amountLD);
    event CancelStake(uint32 indexed srcEid, address indexed srcAsset, address indexed asset, uint256 amountLD);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Forbidden();
    error NotStargate();
    error NativeDisabled();
    error UnsupportedAsset();
    error InvalidMessage();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _endpoint, address _stargate, address _owner) Owned(_owner) {
        endpoint = _endpoint;
        stargate = _stargate;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getAsset(uint32 srcEid, address srcAsset) internal view returns (address) {
        if (srcAsset == address(0)) {
            if (!nativeEnabled[srcEid]) revert NativeDisabled();
            return address(0);
        } else {
            address asset = assets[srcEid][srcAsset];
            if (asset == address(0)) revert UnsupportedAsset();
            return asset;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function updateNativeEnabled(uint32 srcEid, bool enabled) external onlyOwner {
        nativeEnabled[srcEid] = enabled;

        emit UpdateNativeEnabled(srcEid, enabled);
    }

    function updateAsset(uint32 srcEid, address srcAsset, address asset) external onlyOwner {
        assets[srcEid][srcAsset] = asset;

        emit UpdateAsset(srcEid, srcAsset, asset);
    }

    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) external payable {
        if (msg.sender != endpoint) revert Forbidden();
        if (_from != stargate) revert NotStargate();

        try this.stake(_message) { }
        catch (bytes memory reason) {
            failedMessages[_guid] = keccak256(_message);

            emit LzComposeFail(_guid, _message, reason);
        }
    }

    function stake(bytes calldata message) external {
        if (msg.sender != address(this)) revert Forbidden();

        uint32 srcEid = OFTComposeMsgCodec.srcEid(message);
        uint256 amountLD = OFTComposeMsgCodec.amountLD(message);
        bytes memory composeMsg = OFTComposeMsgCodec.composeMsg(message);
        address srcAsset = abi.decode(composeMsg, (address));

        address asset = _getAsset(srcEid, srcAsset);
        _stake(asset, amountLD);

        emit Stake(srcEid, srcAsset, asset, amountLD);
    }

    function retryStake(bytes32 guid, bytes calldata message) external {
        bytes32 hash = failedMessages[guid];
        if (keccak256(message) != hash) revert InvalidMessage();

        uint32 srcEid = OFTComposeMsgCodec.srcEid(message);
        uint256 amountLD = OFTComposeMsgCodec.amountLD(message);
        bytes memory composeMsg = OFTComposeMsgCodec.composeMsg(message);
        address srcAsset = abi.decode(composeMsg, (address));

        address asset = _getAsset(srcEid, srcAsset);
        _stake(asset, amountLD);

        emit Stake(srcEid, srcAsset, asset, amountLD);
    }

    function _stake(address asset, uint256 amountLD) internal virtual;

    function cancelStake(bytes32 guid, bytes calldata message, bytes calldata extra) external payable {
        bytes32 hash = failedMessages[guid];
        if (keccak256(message) != hash) revert InvalidMessage();

        uint32 srcEid = OFTComposeMsgCodec.srcEid(message);
        uint256 amountLD = OFTComposeMsgCodec.amountLD(message);
        bytes memory composeMsg = OFTComposeMsgCodec.composeMsg(message);
        (address srcAsset, address srcRebalancer) = abi.decode(composeMsg, (address, address));

        address asset = _getAsset(srcEid, srcAsset);
        IStargate(stargate).takeTaxi(srcEid, asset, srcRebalancer, amountLD, extra, "");

        emit CancelStake(srcEid, srcAsset, asset, amountLD);
    }

    function stake(address asset, uint256 amountLD) external {
        // TODO

        _stake(asset, amountLD);
    }

    function unstake(address asset, uint256 amountLD) external {
        // TODO
    }

    fallback() external payable { }
    receive() external payable { }
}
