// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ITokenRegistry } from "../interfaces/ITokenRegistry.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TokenRegistry
 * @notice Registry for managing BaseERC20xD tokens that can use UserWallet
 * @dev Only registers tokens, not external protocols like Uniswap or Aave
 */
contract TokenRegistry is Ownable, ITokenRegistry {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITokenRegistry
    mapping(address token => bool registered) public override registeredTokens;

    // Blacklist policy
    mapping(address => bool) public blacklistedTargets;
    mapping(bytes4 => bool) public blacklistedSelectors;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) Ownable(_owner) {
        // Seed default blacklisted selectors (defense-in-depth)
        // ERC20 approvals/transfers
        _blkSel(0x095ea7b3); // approve(address,uint256)
        _blkSel(0x39509351); // increaseAllowance(address,uint256)
        _blkSel(0xa457c2d7); // decreaseAllowance(address,uint256)
        _blkSel(0xa9059cbb); // transfer(address,uint256)
        _blkSel(0x23b872dd); // transferFrom(address,address,uint256)

        // EIP-2612 and DAI-style permit
        _blkSel(0xd505accf); // permit(address,address,uint256,uint256,uint8,bytes32,bytes32)
        _blkSel(0x8fcbaf0c); // permit(address,address,uint256,uint256,bool,uint8,bytes32,bytes32)

        // EIP-3009 authorizations
        _blkSel(0xcf092995); // transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes)
        _blkSel(0x88b7ab63); // receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes)
        _blkSel(0xb7b72899); // cancelAuthorization(address,bytes32,bytes)
        _blkSel(0x5a049a70); // cancelAuthorization(address,bytes32,uint8,bytes32,bytes32)

        // Uniswap Permit2 common
        _blkSel(0x2b67b570); // permit(address,((address,uint160,uint48,uint48),address,uint256),bytes)
        _blkSel(0x35f9eb42); // permitBatch(address,(((address,uint160,uint48,uint48),address,uint256)[]),bytes)
        _blkSel(0x00089b7b); // permitTransferFrom((address,address,uint256,uint256),bytes,address)
        _blkSel(0x42c03417); // permitWitnessTransferFrom((address,address,address,uint256,uint256),address,bytes32,uint256,address,uint256,uint256,bytes)

        // ERC721 / ERC1155 approvals and transfers
        _blkSel(0xa22cb465); // setApprovalForAll(address,bool)
        _blkSel(0x095ea7b3); // approve(address,uint256) // ERC721 approve
        _blkSel(0x42842e0e); // safeTransferFrom(address,address,uint256)
        _blkSel(0xb88d4fde); // safeTransferFrom(address,address,uint256,bytes)
        _blkSel(0x2eb2c2d6); // safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)
        _blkSel(0xf242432a); // safeTransferFrom(address,address,uint256,uint256,bytes) // ERC1155 single

        // ERC1363 call-based transfers/approvals
        _blkSel(0x1296ee62); // transferAndCall(address,uint256)
        _blkSel(0x4000aea0); // transferAndCall(address,uint256,bytes)
        _blkSel(0x3177029f); // approveAndCall(address,uint256)
        _blkSel(0xcae9ca51); // approveAndCall(address,uint256,bytes)
        _blkSel(0xd8fbe994); // transferFromAndCall(address,address,uint256)
        _blkSel(0xc1d34b89); // transferFromAndCall(address,address,uint256,bytes)

        // ERC777 operators
        _blkSel(0x959b8c3f); // authorizeOperator(address)
        _blkSel(0xfad8b32a); // revokeOperator(address)
        _blkSel(0x62ad1b83); // operatorSend(address,address,uint256,bytes,bytes)
        _blkSel(0xfc673c4f); // operatorBurn(address,uint256,bytes,bytes)

        // Multicall/aggregators (best-effort coverage)
        _blkSel(0xac9650d8); // multicall(bytes[])
        _blkSel(0x5ae401dc); // multicall(uint256,bytes[])
        _blkSel(0x252dba42); // aggregate((address,bytes)[])
        _blkSel(0xbce38bd7); // tryAggregate(bool,(address,bytes)[])
        _blkSel(0x82ad56cb); // aggregate3((address,bool,bytes)[])
        _blkSel(0x174dea71); // aggregate3Value((address,bool,uint256,bytes)[])
        _blkSel(0xb1bdad27); // batchExecute((address,bytes)[])
        _blkSel(0xbaae8abf); // execute((address,bytes)[])
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _blkSel(bytes4 sel) internal {
        blacklistedSelectors[sel] = true;
        emit BlacklistSelectorSet(sel, true);
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register or unregister a BaseERC20xD token
     * @dev Only owner can register tokens. This is for YOUR tokens only, not external protocols
     * @param token The BaseERC20xD token address
     * @param status True to register, false to unregister
     */
    function registerToken(address token, bool status) external onlyOwner {
        registeredTokens[token] = status;
        emit TokenRegistered(token, status);
    }

    /**
     * @notice Check if a token is registered
     * @param token The token address to check
     * @return registered True if the token is registered
     */
    function isRegistered(address token) external view returns (bool) {
        return registeredTokens[token];
    }

    /**
     * @notice Check if a (target, selector) pair is blacklisted
     */
    function isBlacklisted(address target, bytes4 selector) external view returns (bool) {
        return blacklistedTargets[target] || blacklistedSelectors[selector];
    }

    /**
     * @notice Batch register multiple tokens
     * @param tokens Array of token addresses
     * @param statuses Array of registration statuses
     */
    function batchRegisterTokens(address[] calldata tokens, bool[] calldata statuses) external onlyOwner {
        if (tokens.length != statuses.length) revert LengthMismatch();

        for (uint256 i = 0; i < tokens.length; i++) {
            registeredTokens[tokens[i]] = statuses[i];
            emit TokenRegistered(tokens[i], statuses[i]);
        }
    }

    /**
     * @notice Set blacklist status for multiple targets
     */
    function setBlacklistedTargets(address[] calldata targets, bool[] calldata flags) external onlyOwner {
        if (targets.length != flags.length) revert LengthMismatch();
        for (uint256 i = 0; i < targets.length; i++) {
            blacklistedTargets[targets[i]] = flags[i];
            emit BlacklistTargetSet(targets[i], flags[i]);
        }
    }

    /**
     * @notice Set blacklist status for multiple function selectors
     */
    function setBlacklistedSelectors(bytes4[] calldata selectors, bool[] calldata flags) external onlyOwner {
        if (selectors.length != flags.length) revert LengthMismatch();
        for (uint256 i = 0; i < selectors.length; i++) {
            blacklistedSelectors[selectors[i]] = flags[i];
            emit BlacklistSelectorSet(selectors[i], flags[i]);
        }
    }
}
