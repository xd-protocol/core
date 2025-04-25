// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import {
    IOFT,
    SendParam,
    MessagingFee,
    MessagingReceipt,
    OFTReceipt,
    OFTLimit,
    OFTFeeDetail
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Ticket } from "stargate/interfaces/IStargate.sol";
import { AddressLib } from "src/libraries/AddressLib.sol";

contract StargatePoolMock {
    using SafeTransferLib for ERC20;

    uint32 public immutable eid;
    address public immutable endpoint;
    address public immutable token;

    mapping(uint32 eid => bytes32) public peers;

    constructor(address _endpoint, address _token) {
        eid = ILayerZeroEndpointV2(_endpoint).eid();
        endpoint = _endpoint;
        token = _token;
    }

    function setPeer(uint32 _eid, bytes32 _peer) external {
        peers[_eid] = _peer;
    }

    function quoteOFT(SendParam calldata _sendParam)
        external
        pure
        returns (OFTLimit memory limit, OFTFeeDetail[] memory details, OFTReceipt memory receipt)
    {
        uint256 amount = _sendParam.amountLD;
        receipt.amountSentLD = amount;
        receipt.amountReceivedLD = amount * 99 / 100;
        return (limit, details, receipt);
    }

    function quoteSend(SendParam calldata, bool) external pure returns (MessagingFee memory) {
        return MessagingFee(0.01e18, 0);
    }

    function sendToken(SendParam calldata _sendParam, MessagingFee calldata, address)
        external
        payable
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt, Ticket memory ticket)
    {
        address peer = AddressLib.fromBytes32(peers[_sendParam.dstEid]);
        require(peer != address(0), "REMOTE_NOT_SET");

        uint256 amount = _sendParam.amountLD;
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        oftReceipt.amountSentLD = amount;
        oftReceipt.amountReceivedLD = amount * 99 / 100;

        address to = AddressLib.fromBytes32(_sendParam.to);
        StargatePoolMock(peer).onReceive(eid, to, oftReceipt.amountReceivedLD, _sendParam.composeMsg);

        return (msgReceipt, oftReceipt, ticket);
    }

    function onReceive(uint32 srcEid, address to, uint256 amountLD, bytes memory composeMsg) external {
        ERC20(token).safeTransfer(address(this), amountLD);
        if (composeMsg.length > 0) {
            bytes memory message =
                OFTComposeMsgCodec.encode(0, srcEid, amountLD, abi.encodePacked(address(this), composeMsg));
            ILayerZeroEndpointV2(endpoint).sendCompose(to, bytes32(0), 0, message);
        }
    }
}
