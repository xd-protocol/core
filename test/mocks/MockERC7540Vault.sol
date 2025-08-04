// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC7540 } from "src/interfaces/IERC7540.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

/**
 * @title MockERC7540Vault
 * @notice Mock implementation of ERC7540 vault for testing
 */
contract MockERC7540Vault is ERC20 {
    address public immutable asset;
    uint256 public nextRequestId = 1;

    struct DepositRequestData {
        address controller;
        address owner;
        uint256 assets;
        uint256 pending;
        uint256 claimable;
    }

    struct RedeemRequestData {
        address controller;
        address owner;
        uint256 shares;
        uint256 pending;
        uint256 claimable;
    }

    mapping(uint256 => DepositRequestData) public depositRequests;
    mapping(uint256 => RedeemRequestData) public redeemRequests;
    mapping(address => mapping(address => bool)) public operators;

    // Events from IERC7540
    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 assets
    );
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares
    );
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    constructor(address _asset) ERC20("Mock Vault", "mVAULT", 18) {
        asset = _asset;
    }

    // ERC4626 Base Functions (minimal implementation)
    function totalAssets() external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets; // 1:1 for simplicity
    }

    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares; // 1:1 for simplicity
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = assets;
        _mint(receiver, shares);
        return shares;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        assets = shares;
        _mint(receiver, shares);
        return assets;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return balanceOf[owner];
    }

    function previewWithdraw(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = assets;
        _burn(owner, shares);
        return shares;
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf[owner];
    }

    function previewRedeem(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = shares;
        _burn(owner, shares);
        return assets;
    }

    // ERC7540 Functions
    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256 requestId) {
        requestId = nextRequestId++;
        depositRequests[requestId] =
            DepositRequestData({ controller: controller, owner: owner, assets: assets, pending: assets, claimable: 0 });

        emit DepositRequest(controller, owner, requestId, msg.sender, assets);
        return requestId;
    }

    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId) {
        requestId = nextRequestId++;
        redeemRequests[requestId] =
            RedeemRequestData({ controller: controller, owner: owner, shares: shares, pending: shares, claimable: 0 });

        emit RedeemRequest(controller, owner, requestId, msg.sender, shares);
        return requestId;
    }

    function pendingDepositRequest(uint256 requestId, address controller) external view returns (uint256) {
        DepositRequestData memory req = depositRequests[requestId];
        if (req.controller != controller) return 0;
        return req.pending;
    }

    function pendingRedeemRequest(uint256 requestId, address controller) external view returns (uint256) {
        RedeemRequestData memory req = redeemRequests[requestId];
        if (req.controller != controller) return 0;
        return req.pending;
    }

    function claimableDepositRequest(uint256 requestId, address controller) external view returns (uint256) {
        DepositRequestData memory req = depositRequests[requestId];
        if (req.controller != controller) return 0;
        return req.claimable;
    }

    function claimableRedeemRequest(uint256 requestId, address controller) external view returns (uint256) {
        RedeemRequestData memory req = redeemRequests[requestId];
        if (req.controller != controller) return 0;
        return req.claimable;
    }

    function setOperator(address operator, bool approved) external returns (bool) {
        operators[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    function isOperator(address controller, address operator) external view returns (bool) {
        return operators[controller][operator];
    }

    // Test helpers
    function setClaimable(uint256 requestId, uint256 amount) external {
        if (depositRequests[requestId].assets > 0) {
            depositRequests[requestId].claimable = amount;
        } else if (redeemRequests[requestId].shares > 0) {
            redeemRequests[requestId].claimable = amount;
        }
    }

    function setPending(uint256 requestId, uint256 amount) external {
        if (depositRequests[requestId].assets > 0) {
            depositRequests[requestId].pending = amount;
        } else if (redeemRequests[requestId].shares > 0) {
            redeemRequests[requestId].pending = amount;
        }
    }
}
