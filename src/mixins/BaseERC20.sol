// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

/**
 * @title BaseERC20
 * @notice An abstract ERC20 contract providing foundational functionality and storage.
 *         It integrates EIP-2612 for permit-based approvals and interacts with an underlying ERC20 token.
 */
abstract contract BaseERC20 {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    address public immutable underlying;

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;
    string public symbol;
    uint8 public immutable decimals;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address account => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientBalance();
    error PermitDeadlineExpired();
    error InvalidSigner();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ERC20 token with metadata and EIP-712 domain separators.
     * @param _underlying The address of the underlying ERC20 token.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param _decimals The number of decimals the token uses.
     */
    constructor(address _underlying, string memory _name, string memory _symbol, uint8 _decimals) {
        underlying = _underlying;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total supply of the token across all chains.
     * @return The total supply of the token as a `uint256`.
     */
    function totalSupply() public view virtual returns (uint256);
    /**
     * @notice Returns the synced balance of a specific account across all chains.
     * @param account The address of the account to query.
     * @return The synced balance of the account as a `uint256`.
     */
    function balanceOf(address account) public view virtual returns (uint256);
    /**
     * @notice Returns the local balance of a specific account on the current chain.
     * @param account The address of the account to query.
     * @return The local balance of the account on this chain as a `uint256`.
     */
    function localBalanceOf(address account) public view virtual returns (uint256);

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approves a spender to transfer up to a specified amount of tokens on behalf of the caller.
     * @param spender The address allowed to spend the tokens.
     * @param amount The maximum amount of tokens the spender is allowed to transfer.
     * @return true if the approval is successful.
     */
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    /**
     * @notice Transfers a specified amount of tokens to another address.
     * @param to The recipient address.
     * @param amount The amount of tokens to transfer.
     * @return true if the transfer is successful.
     */
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _transfer(msg.sender, to, amount);

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    /**
     * @notice Transfers a specified amount of tokens from one address to another, using the caller's allowance.
     * @dev The caller must be approved to transfer the specified amount on behalf of `from`.
     *      The `hasSufficientBalance` modifier ensures that the `from` address has enough local balance.
     * @param from The address from which tokens will be transferred.
     * @param to The recipient address.
     * @param amount The amount of tokens to transfer.
     * @return true if the transfer is successful.
     */
    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _transfer(from, to, amount);

        emit Transfer(from, to, amount);

        return true;
    }

    /**
     * @notice Mints tokens by transferring the underlying ERC20 tokens from the caller to the contract.
     * @param to The recipient address of the minted tokens.
     * @param amount The amount of tokens to mint.
     * @dev This function should be called by derived contracts with appropriate access control.
     */
    function _mint(address to, uint256 amount) internal virtual {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        _transfer(address(0), to, amount);

        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Burns tokens by transferring them to the zero address and returning the underlying ERC20 tokens to the specified address.
     * @param amount The amount of tokens to burn.
     * @param to The address to receive the underlying ERC20 tokens.
     * @dev This function should be called by derived contracts with appropriate access control.
     */
    function _burn(uint256 amount, address to) internal virtual {
        _transfer(msg.sender, address(0), amount);

        emit Transfer(msg.sender, address(0), amount);

        ERC20(underlying).safeTransfer(to, amount);
    }

    /**
     * @notice Transfers tokens from one address to another.
     * @dev This is an abstract function and must be implemented by derived contracts.
     *      It should handle the actual balance updates.
     * @param from The address from which tokens will be transferred.
     * @param to The recipient address.
     * @param amount The amount of tokens to transfer.
     */
    function _transfer(address from, address to, uint256 amount) internal virtual;

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Permits `spender` to spend `value` tokens on behalf of `owner` via EIP-2612 signature.
     * @param owner The address granting the allowance.
     * @param spender The address being granted the allowance.
     * @param value The maximum amount of tokens the spender is allowed to transfer.
     * @param deadline The timestamp by which the permit must be used.
     * @param v The recovery byte of the signature.
     * @param r Half of the ECDSA signature pair.
     * @param s Half of the ECDSA signature pair.
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        if (deadline < block.timestamp) revert PermitDeadlineExpired();

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            if (recoveredAddress == address(0) || recoveredAddress != owner) revert InvalidSigner();

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }
}
