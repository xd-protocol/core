// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Vm, VmLib } from "./libraries/VmLib.sol";
import { Script, console } from "forge-std/Script.sol";
import { LibString } from "solmate/utils/LibString.sol";

abstract contract BaseScript is Script {
    using VmLib for Vm;

    function run() external {
        uint256 privateKey = vm.privateKey();
        vm.startBroadcast(privateKey);
        _run(privateKey, vm.addr(privateKey));
        vm.stopBroadcast();

        _run();
    }

    function _run(uint256 privateKey, address account) internal virtual { }

    function _run() internal virtual { }
}
