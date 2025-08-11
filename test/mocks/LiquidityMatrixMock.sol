// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

contract LiquidityMatrixMock {
    mapping(address => mapping(address => int256)) public liquidity;
    mapping(address => bool) public registeredApps;
    mapping(address => int256) public totalLiquidity;
    mapping(address => bool) public settlerWhitelisted;

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

    function getAggregatedSettledLiquidityAt(address app, address account) external view returns (int256) {
        return liquidity[app][account];
    }

    function getAggregatedFinalizedLiquidityAt(address app, address account) external view returns (int256) {
        return liquidity[app][account];
    }

    function getLiquidityAt(address app, bytes32, address account, uint64) external view returns (int256) {
        return liquidity[app][account];
    }

    function getLiquidityAt(address app, bytes32, uint256, address account, uint64) external view returns (int256) {
        return liquidity[app][account];
    }

    function getDataAt(address, bytes32, bytes32, uint64) external pure returns (bytes memory) {
        return abi.encode("test value", 12_345);
    }

    function getDataAt(address, bytes32, uint256, bytes32, uint64) external pure returns (bytes memory) {
        return abi.encode("test value", 12_345);
    }

    function getTotalLiquidityAt(address app, bytes32, uint64) external view returns (int256) {
        return totalLiquidity[app];
    }

    function getTotalLiquidityAt(address app, bytes32, uint256, uint64) external view returns (int256) {
        return totalLiquidity[app];
    }

    function getAppSetting(address app)
        external
        view
        returns (bool registered, bool syncMappedAccountsOnly, bool useHook, address settler)
    {
        return (registeredApps[app], false, true, address(0));
    }

    function registerApp(bool, bool, address settler) external {
        require(!registeredApps[msg.sender], "App already registered");
        require(settlerWhitelisted[settler], "Invalid settler");
        registeredApps[msg.sender] = true;
    }

    function setTotalLiquidity(address app, int256 amount) external {
        totalLiquidity[app] = amount;
    }

    function updateLocalLiquidity(address account, int256 newLiquidity) external returns (uint256, uint256) {
        require(registeredApps[msg.sender], "App not registered");
        liquidity[msg.sender][account] = newLiquidity;
        return (0, 0); // Return dummy indices
    }

    function updateSettlerWhitelisted(address settler, bool whitelisted) external {
        settlerWhitelisted[settler] = whitelisted;
    }
}
