// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Owned } from "solmate/auth/Owned.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IRebalancer } from "../interfaces/IRebalancer.sol";
import { IStargate, StargateLib } from "../libraries/StargateLib.sol";

contract StaragateRebalancer is Owned, IRebalancer {
    using SafeTransferLib for ERC20;
    using StargateLib for IStargate;

    struct Strategy {
        address stargate;
        address to;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint32 public dstEid;
    mapping(address asset => Strategy) public strategies;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateDstEid(uint32 indexed dstEid);
    event UpdateStrategy(address indexed asset, address indexed stargate, address to);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAddress();
    error UnsupportedAsset();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(uint32 _dstEid, address _owner) Owned(_owner) {
        dstEid = _dstEid;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function updateDstEid(uint32 _dstEid) external onlyOwner {
        dstEid = _dstEid;

        emit UpdateDstEid(_dstEid);
    }

    function updateStrategy(address asset, address stargate, address to) external onlyOwner {
        if (stargate == address(0) && to != address(0) || stargate != address(0) && to == address(0)) {
            revert InvalidAddress();
        }

        strategies[asset] = Strategy(stargate, to);

        emit UpdateStrategy(asset, stargate, to);
    }

    function rebalance(address asset, uint256 amount, bytes calldata extra) external payable {
        Strategy memory strategy = strategies[asset];
        if (strategy.stargate == address(0)) revert UnsupportedAsset();

        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        bytes memory composeMsg = abi.encode(asset, address(this), msg.sender);
        IStargate(strategy.stargate).takeTaxi(dstEid, asset, strategy.to, amount, extra, composeMsg);

        emit Rebalance(asset, amount);
    }

    function withdraw(address asset, address to, uint256 amount) external payable {
        // TODO
    }
}
