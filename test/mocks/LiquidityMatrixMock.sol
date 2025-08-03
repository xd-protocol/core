// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

contract LiquidityMatrixMock {
    mapping(address => mapping(address => int256)) public liquidity;
    mapping(address => bool) public registeredApps;
    mapping(address => int256) public totalLiquidity;

    function getLocalLiquidity(address app, address account) external view returns (int256) {
        return liquidity[app][account];
    }

    function getSettledLiquidity(address app, address account) external view returns (int256) {
        return liquidity[app][account];
    }

    function getLocalTotalLiquidity(address app) external view returns (int256) {
        return totalLiquidity[app];
    }

    function getSettledTotalLiquidity(address app) external view returns (int256) {
        return totalLiquidity[app];
    }

    function updateLocalLiquidity(address account, int256 newLiquidity) external returns (uint256, uint256) {
        require(registeredApps[msg.sender], "App not registered");
        liquidity[msg.sender][account] = newLiquidity;
        return (0, 0); // Return dummy indices
    }

    function registerApp(bool, bool, address) external {
        registeredApps[msg.sender] = true;
    }

    function setTotalLiquidity(address app, int256 amount) external {
        totalLiquidity[app] = amount;
    }
}
