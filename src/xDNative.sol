// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BasexDERC20Wrapper } from "./mixins/BasexDERC20Wrapper.sol";
import { IStakingVault, IStakingVaultNativeCallbacks } from "./interfaces/IStakingVault.sol";
import { AddressLib } from "./libraries/AddressLib.sol";

contract xDNative is BasexDERC20Wrapper, IStakingVaultNativeCallbacks {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public constant NATIVE = address(0);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        uint64 _timeLockPeriod,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _synchronizer,
        address _owner
    ) BasexDERC20Wrapper(NATIVE, _timeLockPeriod, _name, _symbol, _decimals, _synchronizer, _owner) { }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, uint256 minAmount, uint128 gasLimit, uint256 value, address refundTo)
        internal
        override
    {
        if (value < amount) revert InsufficientValue();

        IStakingVault(vault).depositNative{ value: value }(amount, minAmount, gasLimit, refundTo);
    }

    function _withdraw(uint256 amount, bytes memory data, uint128 gasLimit, uint256 value, address refundTo)
        internal
        override
    {
        try IStakingVault(vault).withdrawNative{ value: value }(amount, data, gasLimit, refundTo) { }
        catch (bytes memory reason) {
            _onFailedWithdrawal(amount, data, value, reason);
        }
    }

    // IStakingVaultNativeCallbacks
    function onWithdrawNative(bytes calldata data) external payable nonReentrant {
        if (msg.sender != vault) revert Forbidden();

        (address from, address to) = abi.decode(data, (address, address));
        _transferFrom(from, address(0), msg.value);

        AddressLib.transferNative(to, msg.value);
    }
}
