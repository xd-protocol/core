// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBaseWrappedERC20xD } from "./IBaseWrappedERC20xD.sol";
import { IStakingVaultCallbacks } from "./IStakingVault.sol";

interface IWrappedERC20xD is IBaseWrappedERC20xD, IStakingVaultCallbacks { }
