// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { SendParam, MessagingFee, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { IStargate } from "stargate/interfaces/IStargate.sol";
import { AddressLib } from "./AddressLib.sol";

library StargateLib {
    function quoteSendToken(
        IStargate stargate,
        uint32 dstEid,
        address asset,
        address to,
        uint256 amount,
        bytes memory options,
        bytes memory composeMsg,
        bool takeTaxi
    ) internal view returns (uint256) {
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: AddressLib.toBytes32(to),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: composeMsg,
            oftCmd: takeTaxi ? new bytes(0) : new bytes(1)
        });
        (,, OFTReceipt memory receipt) = stargate.quoteOFT(sendParam);
        sendParam.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory messagingFee = stargate.quoteSend(sendParam, false);
        uint256 fee = messagingFee.nativeFee;
        // when sending native
        if (asset == address(0)) {
            fee += amount;
        }
        return fee;
    }

    function sendToken(
        IStargate stargate,
        uint32 dstEid,
        address asset,
        address to,
        uint256 amount,
        bytes memory options,
        bytes memory composeMsg,
        address refundTo,
        uint256 fee,
        bool takeTaxi
    ) internal {
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: AddressLib.toBytes32(to),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: composeMsg,
            oftCmd: takeTaxi ? new bytes(0) : new bytes(1)
        });
        (,, OFTReceipt memory receipt) = stargate.quoteOFT(sendParam);
        sendParam.minAmountLD = receipt.amountReceivedLD;

        uint256 value = fee;
        // when sending native
        if (asset == address(0)) {
            value += amount;
        }

        uint256 balance = address(this).balance;

        ERC20(asset).approve(address(stargate), amount);
        stargate.sendToken{ value: value }(sendParam, MessagingFee(fee, 0), msg.sender);
        ERC20(asset).approve(address(stargate), 0);

        // refund remainder
        if (refundTo != address(0) && address(this).balance > balance - value) {
            AddressLib.transferNative(refundTo, address(this).balance - balance + msg.value);
        }
    }
}
