// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBaseERC20xDWrapper } from "./IBaseERC20xDWrapper.sol";
import { IStakingVaultCallbacks } from "./IStakingVault.sol";

interface IERC20xDWrapper is IBaseERC20xDWrapper, IStakingVaultCallbacks { }
