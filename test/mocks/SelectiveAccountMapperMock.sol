// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ILiquidityMatrixAccountMapper } from "../../src/interfaces/ILiquidityMatrixAccountMapper.sol";

/**
 * @title SelectiveAccountMapperMock
 * @notice Mock contract that implements selective account mapping
 * @dev Used for testing the shouldMapAccounts functionality
 */
contract SelectiveAccountMapperMock is ILiquidityMatrixAccountMapper {
    mapping(address => mapping(address => bool)) public allowedMappings;
    bool public defaultAllow;

    constructor(bool _defaultAllow) {
        defaultAllow = _defaultAllow;
    }

    function setAllowedMapping(address remoteAccount, address localAccount, bool allowed) external {
        allowedMappings[remoteAccount][localAccount] = allowed;
    }

    function setDefaultAllow(bool _defaultAllow) external {
        defaultAllow = _defaultAllow;
    }

    function shouldMapAccounts(bytes32, /* chainUID */ address remoteAccount, address localAccount)
        external
        view
        override
        returns (bool)
    {
        // Check if there's a specific rule for this mapping
        if (allowedMappings[remoteAccount][localAccount]) {
            return true;
        }

        // Otherwise use the default
        return defaultAllow;
    }
}
