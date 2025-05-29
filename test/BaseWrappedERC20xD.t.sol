// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { Test, Vm, console } from "forge-std/Test.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { WrappedERC20xD } from "src/WrappedERC20xD.sol";
import { BaseWrappedERC20xD } from "src/mixins/BaseWrappedERC20xD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";

contract BaseWrappedERC20xDTest is BaseERC20xDTestHelper {
    ERC20Mock[CHAINS] underlyings;
    address[CHAINS] vaults;

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        underlyings[i] = new ERC20Mock("Mock", "MOCK", 18);
        for (uint256 j; j < users.length; ++j) {
            underlyings[i].mint(users[j], 100e18);
        }
        vaults[i] = makeAddr(string.concat("vault", vm.toString(i)));
        return new WrappedERC20xD(
            address(underlyings[i]),
            vaults[i],
            "xD",
            "xD",
            18,
            address(liquidityMatrices[i]),
            address(gateways[i]),
            owner
        );
    }
}
