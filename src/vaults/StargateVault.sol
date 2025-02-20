// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Owned } from "solmate/auth/Owned.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, Origin, MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { IStakingVault, IStakingVaultCallbacks } from "../interfaces/IStakingVault.sol";
import { IStaker } from "../interfaces/IStaker.sol";
import { AddressLib } from "../libraries/AddressLib.sol";
import { IStargate, StargateLib } from "../libraries/StargateLib.sol";

contract StaragateVault is OApp, IStakingVault {
    using SafeTransferLib for ERC20;
    using StargateLib for IStargate;

    struct Strategy {
        uint32 dstEid;
        address stargate;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint16 public constant WITHDRAW = 1;

    mapping(address asset => Strategy) public strategies;
    mapping(address aset => address) public stakers;

    mapping(uint32 srcEid => mapping(address srcAsset => address)) public assets;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateStrategy(address indexed asset, uint32 dstEid, address indexed stargate);
    event UpdateStaker(address indexed asset, address indexed staker);
    event UpdateAsset(uint32 indexed srcEid, address indexed srcAsset, address indexed asset);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAddress();
    error UnsupportedAsset();
    error Forbidden();
    error InvalidMessageType();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _endpoint, address _owner) OApp(_endpoint, _owner) Ownable(_owner) { }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function quoteWithdraw(address asset, address to, uint256 amount, bytes memory options)
        external
        view
        returns (uint256)
    {
        Strategy memory strategy = strategies[asset];
        MessagingFee memory fee = _quote(strategy.dstEid, abi.encode(WITHDRAW, asset, to, amount), options, false);
        return fee.nativeFee;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function updateStaker(address asset, address staker) external {
        stakers[asset] = staker;

        emit UpdateStaker(asset, staker);
    }

    function stake(address asset, uint256 amount) external {
        address staker = stakers[asset];
        if (staker == address(0)) revert UnsupportedAsset();

        if (asset == address(0)) {
            IStaker(staker).stake{ value: amount }(amount);
        } else {
            ERC20(asset).approve(staker, amount);
            IStaker(staker).stake(amount);
            ERC20(asset).approve(staker, 0);
        }

        emit Stake(asset, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN LOGIC
    //////////////////////////////////////////////////////////////*/

    function updateStrategy(address asset, uint32 dstEid, address stargate) external onlyOwner {
        strategies[asset] = Strategy(dstEid, stargate);

        emit UpdateStrategy(asset, dstEid, stargate);
    }

    function updateAsset(uint32 srcEid, address srcAsset, address asset) external onlyOwner {
        if (srcAsset == address(0)) revert InvalidAddress();

        assets[srcEid][srcAsset] = asset;

        emit UpdateAsset(srcEid, srcAsset, asset);
    }

    function depositIdle(address asset, uint256 amount, bytes calldata options) external payable onlyOwner {
        Strategy memory strategy = strategies[asset];
        if (strategy.stargate == address(0)) revert UnsupportedAsset();

        _deposit(strategy.dstEid, strategy.stargate, asset, amount, options);
    }

    function deposit(address asset, uint256 amount, bytes calldata options) external payable {
        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        Strategy memory strategy = strategies[asset];
        // no need to send tokens if dstEid is current chain
        if (strategy.stargate == address(0)) {
            AddressLib.transferNative(msg.sender, msg.value);
            return;
        }

        _deposit(strategy.dstEid, strategy.stargate, asset, amount, options);
    }

    function _deposit(uint32 dstEid, address stargate, address asset, uint256 amount, bytes calldata options)
        internal
    {
        address peer = AddressLib.fromBytes32(peers[dstEid]);
        if (peer == address(0)) revert NoPeer(dstEid);

        IStargate(stargate).sendToken(dstEid, asset, peer, amount, options, "", msg.sender, 0, false);

        emit Deposit(asset, amount);
    }

    function withdraw(address asset, address to, uint256 amount, bytes calldata options) external payable {
        Strategy memory strategy = strategies[asset];
        // no need to send any cross-chain message if dstEid is current chain
        if (strategy.stargate == address(0)) {
            ERC20(asset).safeTransfer(to, amount);
            AddressLib.transferNative(msg.sender, msg.value);
            IStakingVaultCallbacks(msg.sender).onWithdraw(asset, to, amount);
        } else {
            _lzSend(
                strategy.dstEid,
                abi.encode(WITHDRAW, asset, to, amount),
                options,
                MessagingFee(msg.value, 0),
                payable(msg.sender)
            );
        }
    }

    function _lzReceive(
        Origin calldata, /* _origin */
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal virtual override {
        uint16 mt = abi.decode(_message, (uint16));
        if (mt != WITHDRAW) revert InvalidMessageType();

        // TODO: unstake and send token via stargate
    }

    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable {
        // TODO: handle withdraw
    }
}
