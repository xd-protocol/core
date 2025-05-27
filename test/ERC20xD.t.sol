// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { Test, Vm, console } from "forge-std/Test.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { ERC20xD } from "src/ERC20xD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { LzLib } from "src/libraries/LzLib.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";

contract ERC20xDTest is BaseERC20xDTestHelper {
    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        return new ERC20xD("xD", "xD", 18, address(liquidityMatrices[i]), address(gateways[i]), owner);
    }

    function test_mint(bytes32 seed) public {
        uint256 total;
        for (uint256 i = 1; i < CHAINS; ++i) {
            uint256 amount = (uint256(seed) % 100) * 1e18;
            ERC20xD(address(erc20s[i])).mint(alice, amount);
            total += amount;
            seed = keccak256(abi.encodePacked(seed, i));
        }
        _syncAndSettleLiquidity();

        assertEq(erc20s[0].localBalanceOf(alice), 0);
        assertEq(erc20s[0].balanceOf(alice), total);
    }

    function test_burn() public {
        ERC20xD(address(erc20s[0])).mint(alice, 100e18);
        assertEq(erc20s[0].localBalanceOf(alice), 100e18);
        assertEq(erc20s[0].balanceOf(alice), 100e18);

        changePrank(alice, alice);
        uint256 fee = erc20s[0].quoteTransfer(alice, GAS_LIMIT);
        ERC20xD(address(erc20s[0])).burn{ value: fee }(100e18, LzLib.encodeOptions(GAS_LIMIT, alice));
        _executeTransfer(erc20s[0], alice, 1, "");

        assertEq(erc20s[0].localBalanceOf(alice), 0);
        assertEq(erc20s[0].balanceOf(alice), 0);
    }
}
