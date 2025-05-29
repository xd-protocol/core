// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { BaseERC20xD } from "./BaseERC20xD.sol";
import { IBaseERC20xDWrapper } from "../interfaces/IBaseERC20xDWrapper.sol";

/**
 * @title BaseERC20xDWrapper
 * @notice An abstract extension of BaseERC20xD that adds cross-chain wrapping and unwrapping capabilities.
 * @dev This contract builds upon the core cross-chain liquidity and transfer management provided by
 *      BaseERC20xD by implementing wrapper-specific logic. It introduces additional functionality such as:
 *
 *      - **Wrapping Operations:** Allows users to wrap underlying tokens by transferring tokens from their
 *        account and depositing them, which may trigger an outgoing cross-chain message to update global
 *        liquidity.
 *      - **Unwrapping Operations:** Initiates an unwrap process by calling _transfer(), which performs a global
 *        availability check across chains. This triggers an outgoing cross-chain message to request a redemption.
 *        Once the outgoing message is processed (via incoming cross-chain response), tokens are sent back to
 *        the original chain.
 *      - **Failed Redemption Management:** Records details of failed redemption attempts and allows for their
 *        retry via a designated vault interface.
 *      - **Pending Transfer Management:** Maintains a queue of pending transfers along with nonces to coordinate
 *        cross-chain transfers. Pending transfers are processed upon receiving global liquidity data from remote chains.
 *
 *      **Terminology:**
 *      - *Outgoing messages* are those initiated by this contract (e.g., wrap, unwrap, configuration updates).
 *      - *Incoming messages* refer to cross-chain messages received by this contract (e.g., responses triggering
 *        redemptions).
 *
 *      Derived contracts must implement abstract functions such as _deposit() and _redeem() to provide the
 *      specific logic for handling the deposit and redemption processes associated with wrapping and unwrapping.
 */
abstract contract BaseERC20xDWrapper is BaseERC20xD, IBaseERC20xDWrapper {
    using SafeTransferLib for ERC20;

    struct FailedRedemption {
        bool resolved;
        uint256 shares;
        bytes callbackData;
        bytes receivingData;
        uint128 receivingFee;
        uint256 redeemFee;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable underlying;

    address public vault;

    FailedRedemption[] public failedRedemptions;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateVault(address indexed vault);
    event Wrap(address to, uint256 amount);
    event RedeemFail(uint256 id, bytes reason);
    event Unwrap(address to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidId();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the BaseERC20xDWrapper with the underlying token, and token parameters.
     * @param _underlying The address of the underlying token.
     * @param _vault The vault contract's address.
     * @param _name The token name.
     * @param _symbol The token symbol.
     * @param _decimals The token decimals.
     * @param _liquidityMatrix The address of the LiquidityMatrix contract.
     * @param _gateway The address of the ERC20xDGateway contract.
     * @param _owner The owner of the contract.
     */
    constructor(
        address _underlying,
        address _vault,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner
    ) BaseERC20xD(_name, _symbol, _decimals, _liquidityMatrix, _gateway, _owner) {
        underlying = _underlying;
        vault = _vault;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function quoteUnwrap(address from, uint256 redeemFee, uint128 gasLimit) public view returns (uint256 fee) {
        return quoteTransfer(from, gasLimit) + redeemFee;
    }

    function quoteRedeem(
        address from,
        address to,
        uint256 shares,
        bytes memory receivingData,
        uint128 receivingFee,
        uint256 minAmount,
        uint128 gasLimit
    ) public view virtual returns (uint256 fee);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    fallback() external payable virtual { }

    receive() external payable virtual { }

    function updateVault(address _vault) external onlyOwner {
        vault = _vault;

        emit UpdateVault(_vault);
    }

    /**
     * @notice Wraps underlying tokens by transferring tokens from the caller and depositing them.
     * @dev This is an outgoing operation that involves transferring tokens and initiating a deposit.
     *      Emits a Wrap event upon success.
     * @param to The destination address to receive the wrapped tokens.
     * @param amount The amount of underlying tokens to wrap.
     * @param depositFee The fee to be applied during deposit.
     * @param depositData Additional data for the deposit call.
     */
    function wrap(address to, uint256 amount, uint256 depositFee, bytes memory depositData)
        external
        payable
        virtual
        nonReentrant
        returns (uint256 shares)
    {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        shares = _deposit(amount, depositFee, depositData);

        _transferFrom(address(0), to, shares);

        emit Wrap(to, amount);
    }

    function _deposit(uint256 amount, uint256 fee, bytes memory data) internal virtual returns (uint256 shares);

    /**
     * @notice Initiates an unwrap operation to retrieve underlying tokens from a cross-chain context.
     * @dev This function begins the unwrap process by calling _transfer(), which checks the global token
     *      availability across chains. As a consequence, _executePendingTransfer() is triggered, which in turn
     *      initiates an outgoing cross-chain message to request a redemption (i.e. unwrap). When the outgoing
     *      message is received on the destination chain, a subsequent call to IStakingVault(vault).redeem()
     *      should complete the process by sending the tokens back to the original chain.
     * @param to The destination address to receive the unwrapped tokens.
     * @param shares The amount of the wrapped token.
     * @return receipt A MessagingReceipt confirming the outgoing message initiation.
     */
    function unwrap(
        address to,
        uint256 shares,
        bytes memory receivingData,
        uint128 receivingFee,
        bytes memory redeemData,
        uint256 redeemFee,
        bytes memory readData
    ) external payable virtual nonReentrant returns (MessagingReceipt memory receipt) {
        if (to == address(0)) revert InvalidAddress();

        receipt = _transfer(
            msg.sender, address(0), shares, abi.encode(to, receivingData, receivingFee, redeemData), redeemFee, readData
        );

        emit Unwrap(to, shares);
    }

    /**
     * @notice Processes a pending transfer resulting from an unwrap operation.
     * @dev If the pending transfer indicates an unwrap (i.e. source address is non-zero and destination is zero),
     *      it decodes the call data and invokes the redemption process for an incoming cross-chain message.
     *      Otherwise, it defers to the parent implementation.
     * @param pending The pending transfer data structure.
     */
    function _executePendingTransfer(PendingTransfer memory pending) internal virtual override {
        // only when transferred by unwrap()
        if (pending.from != address(0) && pending.to == address(0)) {
            (address to, bytes memory receivingData, uint128 receivingFee, bytes memory redeemData) =
                abi.decode(pending.callData, (address, bytes, uint128, bytes));
            uint256 shares = pending.amount;
            uint256 redeemFee = pending.value;
            bytes memory callbackData = abi.encode(pending.from, to);
            try this.redeemRestricted(shares, callbackData, receivingData, receivingFee, redeemData, redeemFee) { }
            catch (bytes memory reason) {
                uint256 id = failedRedemptions.length;
                failedRedemptions.push(
                    FailedRedemption(false, shares, callbackData, receivingData, receivingFee, redeemFee)
                );
                emit RedeemFail(id, reason);
            }
        } else {
            super._executePendingTransfer(pending);
        }
    }

    function redeemRestricted(
        uint256 shares,
        bytes memory callbackData,
        bytes memory receivingData,
        uint128 receivingFee,
        bytes memory redeemData,
        uint256 redeemFee
    ) public virtual {
        if (msg.sender != address(this)) revert Forbidden();

        _redeem(shares, callbackData, receivingData, receivingFee, redeemData, redeemFee);
    }

    function _redeem(
        uint256 shares,
        bytes memory callbackData,
        bytes memory receivingData,
        uint128 receivingFee,
        bytes memory redeemData,
        uint256 redeemFen
    ) internal virtual;

    /**
     * @notice Retries a previously failed redemption.
     * @dev Marks the failed redemption as resolved and re-initiates the redemption via the vault contract.
     *      This function requires additional fees (if any) to be provided via msg.value.
     * @param id The identifier of the failed redemption.
     * @param data Additional data for the redemption retry.
     */
    function retryRedeem(uint256 id, bytes memory data) external payable virtual {
        FailedRedemption storage redemption = failedRedemptions[id];
        if (redemption.resolved) revert InvalidId();

        redemption.resolved = true;

        _redeem(
            redemption.shares,
            redemption.callbackData,
            redemption.receivingData,
            redemption.receivingFee,
            data,
            redemption.redeemFee + msg.value
        );
    }
}
