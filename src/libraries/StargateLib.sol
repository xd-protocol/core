// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { SendParam, MessagingFee, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { IStargate } from "stargate/interfaces/IStargate.sol";
import { AddressLib } from "./AddressLib.sol";

library StargateLib {
    function takeTaxi(
        IStargate stargate,
        uint32 dstEid,
        address asset,
        address to,
        uint256 amount,
        bytes memory extra,
        bytes memory composeMsg
    ) internal {
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: AddressLib.toBytes32(to),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: extra,
            composeMsg: composeMsg,
            oftCmd: ""
        });
        (,, OFTReceipt memory receipt) = stargate.quoteOFT(sendParam);
        sendParam.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory messagingFee = stargate.quoteSend(sendParam, false);
        uint256 value = messagingFee.nativeFee;
        // when sending native
        if (asset == address(0)) {
            value += amount;
        }

        ERC20(asset).approve(address(stargate), amount);
        stargate.sendToken{ value: value }(sendParam, messagingFee, msg.sender);
        ERC20(asset).approve(address(stargate), 0);
    }
}
