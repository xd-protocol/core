// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

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

    int256 internal _totalSupply;
    mapping(address account => int256) internal _localBalances;
    mapping(address account => int256) internal _syncedBalances;
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

    error InsufficientBalance();

    /**
     * @notice Ensures that the caller has a sufficient synced balance to perform the operation.
     * @dev This modifier checks that the sender's synced balance is non-negative and greater than or equal to the specified amount.
     *      If the conditions are not met, it reverts with `InsufficientBalance`.
     * @param amount The required amount of tokens for the operation.
     */
    modifier hasSufficientSyncedBalance(uint256 amount) {
        int256 syncedBalance = _syncedBalances[msg.sender];
        if (syncedBalance < 0 || uint256(syncedBalance) < amount) revert InsufficientBalance();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

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
     * @dev The total supply is stored as an `int256` to account for potential negative adjustments during cross-chain synchronization.
     *      If the total supply is negative, the function returns `0` instead of an unsigned integer.
     * @return The total supply of the token as a `uint256`.
     */
    function totalSupply() public view returns (uint256) {
        int256 totalSupply_ = _totalSupply;
        return totalSupply_ < 0 ? 0 : uint256(totalSupply_);
    }

    /**
     * @notice Returns the synced balance of a specific account across all chains.
     * @dev The synced balance is stored as an `int256` to handle adjustments from cross-chain operations.
     *      If the balance is negative, the function returns `0` instead of an unsigned integer.
     * @param account The address of the account to query.
     * @return The synced balance of the account as a `uint256`.
     */
    function balanceOf(address account) public view returns (uint256) {
        int256 syncedBalance = _syncedBalances[account];
        return syncedBalance < 0 ? 0 : uint256(syncedBalance);
    }

    /**
     * @notice Returns the local balance of a specific account on the current chain.
     * @dev The local balance is stored as an `int256` to handle adjustments from synchronization operations.
     *      If the balance is negative, the function returns `0` instead of an unsigned integer.
     * @param account The address of the account to query.
     * @return The local balance of the account on this chain as a `uint256`.
     */
    function localBalanceOf(address account) public view returns (uint256) {
        int256 localBalance = _localBalances[account];
        return localBalance < 0 ? 0 : uint256(localBalance);
    }

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
     * @dev The caller must have a sufficient local balance to perform the transfer.
     *      Uses the `hasSufficientSyncedBalance` modifier to validate the balance.
     * @param to The recipient address.
     * @param amount The amount of tokens to transfer.
     * @return true if the transfer is successful.
     */
    function transfer(address to, uint256 amount) public virtual hasSufficientSyncedBalance(amount) returns (bool) {
        _localBalances[msg.sender] -= int256(amount);
        unchecked {
            _localBalances[to] += int256(amount);
        }

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
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        hasSufficientSyncedBalance(amount)
        returns (bool)
    {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _localBalances[from] -= int256(amount);
        unchecked {
            _localBalances[to] += int256(amount);
        }

        emit Transfer(from, to, amount);

        return true;
    }

    function mint(address to, uint256 amount) public virtual {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        _totalSupply += int256(amount);

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            _localBalances[to] += int256(amount);
            _syncedBalances[to] += int256(amount);
        }

        emit Transfer(address(0), to, amount);
    }

    // function burn(address from, uint256 amount) public virtual hasSufficientSyncedBalance(amount) {
    //     _localBalances[from] -= int256(amount);
    //     _syncedBalances[from] -= int256(amount);
    //
    //     unchecked {
    //         _totalSupply -= int256(amount);
    //     }
    //
    //     emit Transfer(from, address(0), amount);
    //
    //     ERC20(underlying).safeTransferFrom(address(this), msg.sender, amount);
    // }

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

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

            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");

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
