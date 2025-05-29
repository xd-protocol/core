// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBaseERC20xDWrapper } from "./IBaseERC20xDWrapper.sol";
import { IStakingVaultNativeCallbacks } from "./IStakingVault.sol";

interface INativexD is IBaseERC20xDWrapper, IStakingVaultNativeCallbacks { }
