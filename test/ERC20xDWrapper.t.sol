// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { Test, Vm, console } from "forge-std/Test.sol";
import { Settler } from "src/settlers/Settler.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { ERC20xDWrapper } from "src/ERC20xDWrapper.sol";
import { BaseERC20xDWrapper } from "src/mixins/BaseERC20xDWrapper.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { LzLib } from "src/libraries/LzLib.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { StakingVaultMock } from "./mocks/StakingVaultMock.sol";
import { BaseLiquidityMatrixTest } from "./BaseLiquidityMatrixTest.sol";

contract ERC20xDWrapperTest is BaseLiquidityMatrixTest {
    uint8 public constant CHAINS = 8;
    uint64 public constant TIMELOCK_PERIOD = 1 days;
    uint16 public constant CMD_XD_TRANSFER = 1;
    uint96 public constant GAS_LIMIT = 500_000;

    uint32[CHAINS] eids;
    ERC20Mock[CHAINS] underlyings;
    StakingVaultMock vault;
    ILiquidityMatrix[CHAINS] liquidityMatrices;
    address[CHAINS] settlers;
    ERC20xDWrapper[CHAINS] erc20s;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address[] users = [alice, bob, charlie];

    function setUp() public override {
        super.setUp();
        setUpEndpoints(CHAINS, LibraryType.UltraLightNode);

        changePrank(owner, owner);
        address[] memory oapps = new address[](CHAINS);
        address[] memory _erc20s = new address[](CHAINS);
        vault = new StakingVaultMock();
        for (uint32 i; i < CHAINS; ++i) {
            eids[i] = i + 1;
            underlyings[i] = new ERC20Mock("Mock", "MOCK", 18);
            liquidityMatrices[i] = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[eids[i]], owner);
            settlers[i] = address(new Settler(address(liquidityMatrices[i])));
            oapps[i] = address(liquidityMatrices[i]);
            erc20s[i] = new ERC20xDWrapper(
                address(underlyings[i]),
                TIMELOCK_PERIOD,
                address(vault),
                "xD",
                "xD",
                18,
                address(liquidityMatrices[i]),
                owner
            );
            _erc20s[i] = address(erc20s[i]);

            liquidityMatrices[i].updateSettlerWhitelisted(settlers[i], true);
            vm.label(address(liquidityMatrices[i]), string.concat("LiquidityMatrix", vm.toString(i)));
            vm.label(address(erc20s[i]), string.concat("ERC20xDWrapper", vm.toString(i)));
            vm.deal(settlers[i], 1000e18);
        }

        wireOApps(address[](oapps));
        wireOApps(address[](_erc20s));

        for (uint32 i; i < CHAINS; ++i) {
            vm.deal(address(erc20s[i]), 1000e18);
            changePrank(address(erc20s[i]), address(erc20s[i]));
            liquidityMatrices[i].registerApp(false, false, settlers[i]);

            ILiquidityMatrix.ChainConfig[] memory configs = new ILiquidityMatrix.ChainConfig[](CHAINS - 1);
            uint32 count;
            for (uint32 j; j < CHAINS; ++j) {
                if (i == j) continue;
                configs[count++] = ILiquidityMatrix.ChainConfig(eids[j], 0);
                liquidityMatrices[i].updateRemoteApp(eids[j], address(erc20s[j]));
            }

            changePrank(owner, owner);
            liquidityMatrices[i].configChains(configs);
            for (uint256 j; j < users.length; ++j) {
                underlyings[i].mint(users[j], 100e18);
            }
        }

        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 10_000e18);
        }
    }

    function test_wrap() public {
        ERC20xDWrapper local = erc20s[0];

        changePrank(alice, alice);

        uint256 amount = 1e18;
        (uint256 minAmount, uint256 fee) = vault.quoteDeposit(address(underlyings[0]), amount, GAS_LIMIT);

        underlyings[0].approve(address(local), amount);
        uint256 shares = local.wrap(alice, amount, minAmount, fee, LzLib.encodeOptions(GAS_LIMIT, alice));

        assertEq(local.balanceOf(alice), shares);
        assertEq(vault.sharesOf(alice), shares);
        assertEq(underlyings[0].balanceOf(address(vault)), amount);
    }

    function test_unwrap() public {
        ERC20xDWrapper local = erc20s[0];

        changePrank(alice, alice);

        uint256 amount = 1e18;
        (uint256 minAmount, uint256 fee) = vault.quoteDeposit(address(underlyings[0]), amount, GAS_LIMIT);

        underlyings[0].approve(address(local), amount);
        bytes memory options = LzLib.encodeOptions(GAS_LIMIT, alice);
        uint256 shares = local.wrap(alice, amount, minAmount, fee, options);

        uint256 incomingFee;
        (minAmount, incomingFee) = vault.quoteDeposit(address(underlyings[0]), shares, GAS_LIMIT);
        bytes memory incomingData = abi.encode(alice, alice); // from, to
        uint256 outgoingFee = vault.quoteRedeem(
            address(underlyings[0]), alice, shares, minAmount, incomingData, uint128(incomingFee), options, GAS_LIMIT
        );
        uint256 readFee = local.quoteUnwrap(alice, GAS_LIMIT);
        local.unwrap{ value: incomingFee + outgoingFee + readFee }(
            alice, shares, minAmount, uint128(incomingFee), options, uint128(outgoingFee), options, options
        );

        // verifyPackets();

        assertEq(local.balanceOf(alice), 0);
        assertEq(vault.sharesOf(alice), 0);
        assertEq(underlyings[0].balanceOf(alice), minAmount);
    }
}
