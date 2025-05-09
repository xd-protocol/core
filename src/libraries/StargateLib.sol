// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { SendParam, MessagingFee, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { IStargate } from "stargate/interfaces/IStargate.sol";
import { AddressLib } from "./AddressLib.sol";

library StargateLib {
    using SafeTransferLib for ERC20;
    using OptionsBuilder for bytes;

    address constant NATIVE = address(0);

    /**
     * @notice Provides a quote for sending tokens via the Stargate protocol.
     * @dev Constructs a SendParam struct and queries the Stargate contract for an OFT receipt and messaging fee.
     * If the asset is native, the fee is increased by the amount to be sent.
     * @param stargate The Stargate contract interface.
     * @param dstEid The destination endpoint identifier.
     * @param asset The asset to be sent (use NATIVE for native currency).
     * @param to The recipient address on the destination chain.
     * @param amount The amount to be sent.
     * @param composeMsg Arbitrary data to be composed with the message.
     * @param gasLimit The gas limit for executing the cross-chain call.
     * @param takeTaxi A boolean flag that toggles the use of a specific oftCmd value.
     * @return dstAmount The amount expected to be received on the destination chain.
     * @return fee The calculated messaging fee (plus token amount if sending native currency).
     */
    function quoteSendToken(
        IStargate stargate,
        uint32 dstEid,
        address asset,
        address to,
        uint256 amount,
        bytes memory composeMsg,
        uint128 gasLimit,
        bool takeTaxi
    ) internal view returns (uint256 dstAmount, uint256 fee) {
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: AddressLib.toBytes32(to),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0),
            composeMsg: composeMsg,
            oftCmd: takeTaxi ? new bytes(0) : new bytes(1)
        });
        (,, OFTReceipt memory receipt) = stargate.quoteOFT(sendParam);
        sendParam.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory messagingFee = stargate.quoteSend(sendParam, false);
        fee = messagingFee.nativeFee;
        if (asset == NATIVE) {
            fee += amount;
        }
        return (receipt.amountReceivedLD, fee);
    }

    /**
     * @notice Sends tokens via the Stargate protocol.
     * @dev Constructs a SendParam struct and calls the sendToken function on the Stargate contract.
     * Handles ERC20 approval if the asset is not native and refunds any excess native currency.
     * @param stargate The Stargate contract interface.
     * @param dstEid The destination endpoint identifier.
     * @param asset The asset to be sent (use NATIVE for native currency).
     * @param to The recipient address on the destination chain.
     * @param amount The amount to send.
     * @param minAmount The minimum amount acceptable on the destination chain.
     * @param composeMsg Arbitrary data to be composed with the message.
     * @param gasLimit The gas limit for executing the cross-chain call.
     * @param takeTaxi A boolean flag that toggles the use of a specific oftCmd value.
     * @param fee The messaging fee to be paid.
     * @param refundTo The address to which any excess native currency will be refunded.
     * @return dstAmount The amount received on the destination chain as reported by the OFT receipt.
     */
    function sendToken(
        IStargate stargate,
        uint32 dstEid,
        address asset,
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory composeMsg,
        uint128 gasLimit,
        bool takeTaxi,
        uint256 fee,
        address refundTo
    ) internal returns (uint256 dstAmount) {
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: AddressLib.toBytes32(to),
            amountLD: amount,
            minAmountLD: minAmount,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0),
            composeMsg: composeMsg,
            oftCmd: takeTaxi ? new bytes(0) : new bytes(1)
        });

        uint256 balance = address(this).balance;

        uint256 value = fee;
        if (asset == NATIVE) {
            value += amount;
        } else {
            ERC20(asset).safeApprove(address(stargate), 0);
            ERC20(asset).safeApprove(address(stargate), amount);
        }
        (, OFTReceipt memory receipt,) = stargate.sendToken{ value: value }(sendParam, MessagingFee(fee, 0), msg.sender);

        // refund remainder
        if (refundTo != address(0) && address(this).balance > balance - value) {
            AddressLib.transferNative(refundTo, address(this).balance + value - balance);
        }

        return receipt.amountReceivedLD;
    }
}
