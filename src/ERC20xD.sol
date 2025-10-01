// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseERC20xD } from "./mixins/BaseERC20xD.sol";
import { IERC20xD } from "./interfaces/IERC20xD.sol";

/**
 * @title ERC20xD
 * @notice A concrete implementation of a cross-chain ERC20 token with full transfer and liquidity management capabilities
 * @dev Extends BaseERC20xD to provide a complete cross-chain token implementation that can be deployed directly.
 *      Inherits all functionality including pending transfers, hooks, cross-chain reads, and liquidity tracking.
 */
contract ERC20xD is BaseERC20xD, IERC20xD {
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ERC20xD contract.
     * @param _name The token name.
     * @param _symbol The token symbol.
     * @param _decimals The token decimals.
     * @param _liquidityMatrix The address of the LiquidityMatrix contract.
     * @param _gateway The address of the Gateway contract.
     * @param _owner The owner of this contract.
     * @param _settler The address of the whitelisted settler for this token.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner,
        address _settler
    ) BaseERC20xD(_name, _symbol, _decimals, _liquidityMatrix, _gateway, _owner, _settler) { }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20xD
    function quoteBurn(address from, uint128 gasLimit) external view returns (uint256 fee) {
        return quoteTransfer(from, gasLimit);
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20xD
    receive() external payable virtual { }

    /// @inheritdoc IERC20xD
    function mint(address to, uint256 amount) external onlyOwner {
        _transferFrom(address(0), to, amount);
    }

    /// @inheritdoc IERC20xD
    function burn(uint256 amount, bytes calldata data) external payable returns (bytes32 guid) {
        return _transfer(msg.sender, address(0), amount, "", 0, data);
    }
}
