// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBaseWrappedERC20xD } from "./IBaseWrappedERC20xD.sol";
import { IStakingVaultNativeCallbacks } from "./IStakingVault.sol";

interface INativexD is IBaseWrappedERC20xD, IStakingVaultNativeCallbacks { }
