No files changed, compilation skipped

Ran 9 tests for test/WrappedERC20xD.hooks.t.sol:WrappedERC20xDHooksTest
[PASS] test_concurrentUnwrapsFromMultipleUsers() (gas: 869154)
[PASS] test_dataParameterPropagation() (gas: 1020321)
[PASS] test_multipleHooksExecutionOrder() (gas: 2237501)
[PASS] test_unwrapFullAmountWithHook() (gas: 491158)
[PASS] test_unwrapToDifferentRecipient() (gas: 1118121)
[PASS] test_unwrapWithFailingHook_stillBurnsTokens() (gas: 492639)
[PASS] test_unwrapWithMultipleHooks_oneFails() (gas: 604023)
[PASS] test_unwrapWithNoHooks() (gas: 368815)
[PASS] test_unwrapWithRedemptionHook() (gas: 522675)
Suite result: ok. 9 passed; 0 failed; 0 skipped; finished in 9.73ms (2.15ms CPU time)

Ran 11 tests for test/libraries/AddressLib.t.sol:AddressLibTest
[PASS] testFuzz_transferNative_amounts(uint256) (runs: 256, μ: 59916, ~: 60164)
[PASS] testFuzz_transferNative_toEOA(address,uint256) (runs: 256, μ: 59736, ~: 60356)
[PASS] test_transferNative_insufficientBalance_reverts() (gas: 62167)
[PASS] test_transferNative_maxUint256_reverts() (gas: 62196)
[PASS] test_transferNative_multipleTransfers() (gas: 286804)
[PASS] test_transferNative_toEOA() (gas: 61142)
[PASS] test_transferNative_toNonPayableContract_reverts() (gas: 37637)
[PASS] test_transferNative_toPayableContract() (gas: 60864)
[PASS] test_transferNative_toRevertingContract_reverts() (gas: 37727)
[PASS] test_transferNative_toSelf() (gas: 31265)
[PASS] test_transferNative_zeroAmount() (gas: 26407)
Suite result: ok. 11 passed; 0 failed; 0 skipped; finished in 36.74ms (30.03ms CPU time)

Ran 13 tests for test/WrappedERC20xD.t.sol:WrappedERC20xDTest
[PASS] test_constructor() (gas: 26154)
[PASS] test_fallback() (gas: 38072)
[PASS] test_quoteUnwrap() (gas: 399620)
[PASS] test_quoteWrap() (gas: 6124)
[PASS] test_receive() (gas: 38025)
[PASS] test_unwrap_basic() (gas: 2082143)
[PASS] test_unwrap_differentRecipient() (gas: 2037410)
[PASS] test_unwrap_revertZeroAddress() (gas: 468722)
[PASS] test_wrap_basic() (gas: 516068)
[PASS] test_wrap_differentRecipient() (gas: 529707)
[PASS] test_wrap_multipleUsers() (gas: 838643)
[PASS] test_wrap_revertZeroAddress() (gas: 37077)
[PASS] test_wrap_revertZeroAmount() (gas: 37364)
Suite result: ok. 13 passed; 0 failed; 0 skipped; finished in 56.46ms (5.04ms CPU time)

Ran 14 tests for test/NativexD.t.sol:NativexDTest
[PASS] test_constructor() (gas: 24017)
[PASS] test_fallback() (gas: 38072)
[PASS] test_quoteUnwrap() (gas: 399542)
[PASS] test_quoteWrap() (gas: 6070)
[PASS] test_receive() (gas: 38036)
[PASS] test_unwrap_basic() (gas: 2054180)
[PASS] test_unwrap_differentRecipient() (gas: 2009450)
[PASS] test_unwrap_revertZeroAddress() (gas: 440799)
[PASS] test_wrap_basic() (gas: 466672)
[PASS] test_wrap_differentRecipient() (gas: 501732)
[PASS] test_wrap_multipleUsers() (gas: 792503)
[PASS] test_wrap_revertInsufficientValue() (gas: 37203)
[PASS] test_wrap_revertZeroAddress() (gas: 43533)
[PASS] test_wrap_revertZeroAmount() (gas: 37200)
Suite result: ok. 14 passed; 0 failed; 0 skipped; finished in 68.34ms (4.94ms CPU time)

Ran 46 tests for test/mixins/BaseERC20xD.hooks.t.sol:BaseERC20xDHooksTest
[PASS] test_addHook() (gas: 118603)
[PASS] test_addHook_revertAlreadyAdded() (gas: 131080)
[PASS] test_addHook_revertNonOwner() (gas: 36508)
[PASS] test_addHook_revertZeroAddress() (gas: 33967)
[PASS] test_afterTransfer_called() (gas: 407275)
[PASS] test_afterTransfer_calledAfterBalanceUpdate() (gas: 443023)
[PASS] test_afterTransfer_multipleHooks() (gas: 1020610)
[PASS] test_afterTransfer_revertDoesNotBlockTransfer() (gas: 382938)
[PASS] test_allCallbackHooks_inSettlementFlow() (gas: 705287)
[PASS] test_allHooks_inCompleteTransferFlow() (gas: 795467)
[PASS] test_beforeTransfer_called() (gas: 407343)
[PASS] test_beforeTransfer_calledBeforeBalanceUpdate() (gas: 418413)
[PASS] test_beforeTransfer_multipleHooks() (gas: 1020747)
[PASS] test_beforeTransfer_revertDoesNotBlockTransfer() (gas: 384876)
[PASS] test_getHooks() (gas: 199571)
[PASS] test_hookOrdering_maintained() (gas: 2666072)
[PASS] test_hookOrdering_onInitiateTransfer() (gas: 2651782)
[PASS] test_hookOrdering_onMapAccounts() (gas: 2521324)
[PASS] test_hooks_calledOnBurnScenario() (gas: 361090)
[PASS] test_hooks_calledOnMintScenario() (gas: 378262)
[PASS] test_hooks_calledOnSelfTransfer() (gas: 371784)
[PASS] test_onInitiateTransfer_called() (gas: 824750)
[PASS] test_onInitiateTransfer_multipleHooks() (gas: 816512)
[PASS] test_onInitiateTransfer_revertDoesNotBlockTransfer() (gas: 333952)
[PASS] test_onMapAccounts_called() (gas: 271202)
[PASS] test_onMapAccounts_multipleHooks() (gas: 663463)
[PASS] test_onMapAccounts_revertDoesNotBlock() (gas: 202276)
[PASS] test_onMapAccounts_revertNonLiquidityMatrix() (gas: 35842)
[PASS] test_onReadGlobalAvailability_called() (gas: 790013)
[PASS] test_onReadGlobalAvailability_multipleHooks() (gas: 1840167)
[PASS] test_onReadGlobalAvailability_revertDoesNotBlockTransfer() (gas: 743749)
[PASS] test_onSettleData_called() (gas: 371714)
[PASS] test_onSettleData_multipleHooks() (gas: 662544)
[PASS] test_onSettleData_revertDoesNotBlock() (gas: 202515)
[PASS] test_onSettleData_revertNonLiquidityMatrix() (gas: 34993)
[PASS] test_onSettleLiquidity_called() (gas: 272198)
[PASS] test_onSettleLiquidity_multipleHooks() (gas: 662532)
[PASS] test_onSettleLiquidity_revertDoesNotBlock() (gas: 200884)
[PASS] test_onSettleLiquidity_revertNonLiquidityMatrix() (gas: 34763)
[PASS] test_onSettleTotalLiquidity_called() (gas: 243261)
[PASS] test_onSettleTotalLiquidity_multipleHooks() (gas: 593328)
[PASS] test_onSettleTotalLiquidity_revertDoesNotBlock() (gas: 197459)
[PASS] test_onSettleTotalLiquidity_revertNonLiquidityMatrix() (gas: 34263)
[PASS] test_removeHook() (gas: 307063)
[PASS] test_removeHook_revertNonOwner() (gas: 131280)
[PASS] test_removeHook_revertNotFound() (gas: 38501)
Suite result: ok. 46 passed; 0 failed; 0 skipped; finished in 4.48ms (3.59ms CPU time)

Ran 15 tests for test/hooks/ERC7540Hook.t.sol:ERC7540HookTest
[PASS] test_complexFlow_multipleUsersAndChains() (gas: 6082364)
[PASS] test_crossChainTransfer_withHook() (gas: 2881672)
[PASS] test_deployment() (gas: 193408)
[PASS] test_deployment_revertsInvalidVault() (gas: 5740)
[PASS] test_depositAssets() (gas: 98536)
[PASS] test_fullFlow_wrapDepositRedeemUnwrap() (gas: 3166683)
[PASS] test_hookRegistration() (gas: 138598)
[PASS] test_removeHook() (gas: 492294)
[PASS] test_unwrap_invalidAddress_reverts() (gas: 483660)
[PASS] test_unwrap_partialAmount() (gas: 2837531)
[PASS] test_unwrap_triggersRedeem() (gas: 2818329)
[PASS] test_viewFunctions_delegateToVault() (gas: 3104520)
[PASS] test_wrap_multipleUsers() (gas: 1123682)
[PASS] test_wrap_triggersDeposit_withAssets() (gas: 688766)
[PASS] test_wrap_withoutAssets_stillMints() (gas: 506735)
Suite result: ok. 15 passed; 0 failed; 0 skipped; finished in 74.27ms (14.94ms CPU time)

Ran 11 tests for test/hooks/DividendDistributorHook.t.sol:DividendDistributorHookTest
[PASS] test_claimDividends_basic() (gas: 10788352)
[PASS] test_claimDividends_insufficientFee() (gas: 4135812)
[PASS] test_claimDividends_noDividends() (gas: 447598)
[PASS] test_claimDividends_onlyRegistered() (gas: 3118616)
[PASS] test_depositDividend_noSharesReverts() (gas: 2768367)
[PASS] test_depositDividend_viaTransfer() (gas: 2699001)
[PASS] test_emergencyWithdraw() (gas: 5021295)
[PASS] test_emergencyWithdraw_onlyOwner() (gas: 244372)
[PASS] test_pendingDividends_calculation() (gas: 9238419)
[PASS] test_shareUpdate_transfer() (gas: 4967951)
[PASS] test_sharesTracking_onlyRegistered() (gas: 33523)
Suite result: ok. 11 passed; 0 failed; 0 skipped; finished in 111.32ms (34.45ms CPU time)

Ran 22 tests for test/libraries/SnapshotsLib.t.sol:SnapshotsLibTest
[PASS] testFuzz_setAsInt(int256,uint256) (runs: 256, μ: 93090, ~: 93168)
[PASS] testFuzz_set_and_get(uint256,uint256) (runs: 256, μ: 93640, ~: 93718)
[PASS] testFuzz_set_past_timestamps(uint256[5],uint256[5]) (runs: 256, μ: 379032, ~: 380642)
[PASS] test_alternating_past_future_inserts() (gas: 511913)
[PASS] test_binary_search_boundaries() (gas: 715519)
[PASS] test_get_empty_snapshots() (gas: 3168)
[PASS] test_large_number_of_snapshots() (gas: 6745230)
[PASS] test_setAsInt_and_getAsInt() (gas: 230106)
[PASS] test_setAsInt_with_timestamp() (gas: 233448)
[PASS] test_set_and_get_multiple_sequential() (gas: 233228)
[PASS] test_set_and_get_single() (gas: 90608)
[PASS] test_set_max_value() (gas: 92839)
[PASS] test_set_past_timestamp_complex_sequence() (gas: 666303)
[PASS] test_set_past_timestamp_insert_beginning() (gas: 299781)
[PASS] test_set_past_timestamp_insert_middle() (gas: 368647)
[PASS] test_set_past_timestamp_multiple() (gas: 377302)
[PASS] test_set_past_timestamp_single() (gas: 163309)
[PASS] test_set_same_value_different_timestamps() (gas: 228929)
[PASS] test_set_zero_value() (gas: 72932)
[PASS] test_update_existing_timestamp() (gas: 229258)
[PASS] test_update_last_timestamp() (gas: 229770)
[PASS] test_update_past_timestamp() (gas: 229240)
Suite result: ok. 22 passed; 0 failed; 0 skipped; finished in 44.76ms (44.64ms CPU time)

Ran 24 tests for test/libraries/ArrayLib.t.sol:ArrayLibTest
[PASS] testFuzz_insertSorted_maintainsSortedProperty(uint256[]) (runs: 256, μ: 304094, ~: 306342)
[PASS] testFuzz_insertSorted_multipleValues(uint256[10]) (runs: 256, μ: 261640, ~: 263967)
[PASS] testFuzz_insertSorted_singleValue(uint256) (runs: 256, μ: 44659, ~: 44970)
[PASS] testFuzz_insertSorted_twoValues(uint256,uint256) (runs: 256, μ: 67858, ~: 67887)
[PASS] test_insertSorted_consecutiveValues() (gas: 136174)
[PASS] test_insertSorted_duplicateValue_beginning() (gas: 114485)
[PASS] test_insertSorted_duplicateValue_end() (gas: 113195)
[PASS] test_insertSorted_duplicateValue_middle() (gas: 114030)
[PASS] test_insertSorted_emptyArray() (gas: 44963)
[PASS] test_insertSorted_gasOptimization_appendOnly() (gas: 233782)
Logs:
  Gas used for 10 append operations: 228162

[PASS] test_insertSorted_gasOptimization_prependOnly() (gas: 274268)
Logs:
  Gas used for 10 prepend operations: 269148

[PASS] test_insertSorted_largeArray_random() (gas: 1464708)
[PASS] test_insertSorted_largeArray_reverse() (gas: 4462689)
[PASS] test_insertSorted_largeArray_sequential() (gas: 2278374)
[PASS] test_insertSorted_maxValue() (gas: 90485)
[PASS] test_insertSorted_multipleDuplicates() (gas: 159978)
[PASS] test_insertSorted_multipleElements_beginning() (gas: 114755)
[PASS] test_insertSorted_multipleElements_end() (gas: 113175)
[PASS] test_insertSorted_multipleElements_middle() (gas: 114504)
[PASS] test_insertSorted_randomOrder() (gas: 209982)
[PASS] test_insertSorted_reverseOrder() (gas: 141425)
[PASS] test_insertSorted_singleElement_after() (gas: 67799)
[PASS] test_insertSorted_singleElement_before() (gas: 68502)
[PASS] test_insertSorted_zeroValue() (gas: 71716)
Suite result: ok. 24 passed; 0 failed; 0 skipped; finished in 270.13ms (290.90ms CPU time)

Ran 28 tests for test/ERC20xD.t.sol:ERC20xDTest
[PASS] test_burn_basic() (gas: 2294444)
[PASS] test_burn_crossChain() (gas: 8457183)
[PASS] test_burn_fullBalance() (gas: 2279259)
[PASS] test_burn_multipleChains() (gas: 18189440)
[PASS] test_burn_revertInsufficientBalance() (gas: 283301)
[PASS] test_burn_revertPendingTransfer() (gas: 1638012)
[PASS] test_cancelPendingTransfer() (gas: 7583627)
[PASS] test_cancelPendingTransfer_revertNotPending() (gas: 38272)
[PASS] test_integration_crossChainMintBurn() (gas: 19484406)
[PASS] test_integration_mintBurnCycle() (gas: 8315085)
[PASS] test_mint_basic() (gas: 193311)
[PASS] test_mint_multipleChains() (gas: 7122688)
[PASS] test_mint_randomAmounts(bytes32) (runs: 256, μ: 6873966, ~: 6875725)
[PASS] test_mint_revertNonOwner() (gas: 36832)
[PASS] test_mint_toZeroAddress() (gas: 151726)
[PASS] test_onRead_revertForbidden() (gas: 35596)
[PASS] test_quoteBurn() (gas: 397026)
[PASS] test_reduce() (gas: 33213)
[PASS] test_reduce_revertInvalidRequests() (gas: 13115)
[PASS] test_transferFrom_revertNotComposing() (gas: 85799)
[PASS] test_transfer_crossChain_basic() (gas: 8437617)
[PASS] test_transfer_crossChain_revertInsufficientBalance() (gas: 286163)
[PASS] test_transfer_crossChain_revertInsufficientValue() (gas: 6073526)
[PASS] test_transfer_crossChain_revertInvalidAddress() (gas: 6186472)
[PASS] test_transfer_crossChain_revertOverflow() (gas: 6188940)
[PASS] test_transfer_crossChain_revertTransferPending() (gas: 7633828)
[PASS] test_transfer_crossChain_revertZeroAmount() (gas: 6188911)
[PASS] test_transfer_crossChain_withCallData() (gas: 8789648)
Suite result: ok. 28 passed; 0 failed; 0 skipped; finished in 986.05ms (975.82ms CPU time)

Ran 31 tests for test/libraries/MerkleTreeLib.t.sol:MerkleTreeLibTest
[PASS] test_allZeroValues() (gas: 25427)
[PASS] test_computeRoot_emptyTree() (gas: 721)
[PASS] test_computeRoot_evenNumberOfNodes() (gas: 7012)
[PASS] test_computeRoot_invalidLengths() (gas: 5546)
[PASS] test_computeRoot_matchesIncrementalUpdate(uint256) (runs: 256, μ: 38796701, ~: 39585078)
[PASS] test_computeRoot_oddNumberOfNodes() (gas: 6096)
[PASS] test_computeRoot_singleNode() (gas: 1823)
[PASS] test_consecutiveUpdates_maintainsConsistency() (gas: 429039)
[PASS] test_getProof_invalidIndex() (gas: 7424)
[PASS] test_getProof_invalidLengths() (gas: 7593)
[PASS] test_getProof_nonPowerOfTwo() (gas: 109522)
[PASS] test_getProof_powerOfTwo() (gas: 131474)
[PASS] test_getProof_singleNode() (gas: 1575)
[PASS] test_getProof_twoNodes() (gas: 6308)
[PASS] test_identicalKeys_differentValues() (gas: 25450)
[PASS] test_initialize() (gas: 4595)
[PASS] test_largeTree_gasConsumption() (gas: 499279)
Logs:
  Gas used for computing root of 256 nodes: 194215
  Gas used for getting proof from 256 nodes: 241482
  Gas used for verifying proof: 2966

[PASS] test_updateExistingValue_preservesTreeStructure() (gas: 774239)
[PASS] test_update_duplicateKey() (gas: 91046)
[PASS] test_update_largeTree(uint256) (runs: 256, μ: 76553997, ~: 76553997)
[PASS] test_update_multipleNodes() (gas: 252672)
[PASS] test_update_sequentialKeys() (gas: 769837)
[PASS] test_update_singleNode() (gas: 90125)
[PASS] test_verifyProof_emptyProof() (gas: 2004)
[PASS] test_verifyProof_fuzz(uint256) (runs: 256, μ: 107891, ~: 97941)
[PASS] test_verifyProof_invalidProof() (gas: 10128)
[PASS] test_verifyProof_validProof() (gas: 10046)
[PASS] test_verifyProof_wrongIndex() (gas: 10048)
[PASS] test_verifyProof_wrongKey() (gas: 9983)
[PASS] test_verifyProof_wrongRoot() (gas: 10072)
[PASS] test_verifyProof_wrongValue() (gas: 10004)
Suite result: ok. 31 passed; 0 failed; 0 skipped; finished in 7.62s (11.79s CPU time)

Ran 44 tests for test/mixins/BaseERC20xD.t.sol:BaseERC20xDTest
[PASS] test_availableLocalBalanceOf() (gas: 7553473)
[PASS] test_balanceOf() (gas: 6096429)
[PASS] test_cancelPendingTransfer() (gas: 7583601)
[PASS] test_cancelPendingTransfer_revertNotPending() (gas: 38295)
[PASS] test_constructor() (gas: 33156)
[PASS] test_crossChainTransfer_basic() (gas: 9074407)
[PASS] test_crossChainTransfer_composable() (gas: 2719767)
[PASS] test_crossChainTransfer_exceedsGlobalBalance() (gas: 6379386)
[PASS] test_crossChainTransfer_insufficientValueForNative() (gas: 6283058)
[PASS] test_crossChainTransfer_localBalanceGoesNegative() (gas: 8709902)
[PASS] test_crossChainTransfer_maxAmountTransfer() (gas: 6315792)
[PASS] test_crossChainTransfer_multipleAccountsSimultaneous() (gas: 18709256)
[PASS] test_crossChainTransfer_multipleChainsConcurrent() (gas: 19155765)
[PASS] test_crossChainTransfer_multipleChainsSameAccount() (gas: 18732288)
[PASS] test_crossChainTransfer_preventDoubleSpending() (gas: 16166665)
[PASS] test_crossChainTransfer_raceConditionSameAccountSameChain() (gas: 16301480)
[PASS] test_crossChainTransfer_revertInsufficientAvailability() (gas: 10948228)
[PASS] test_crossChainTransfer_revertInsufficientBalance() (gas: 7736304)
[PASS] test_crossChainTransfer_revertTransferPending() (gas: 1707417)
[PASS] test_crossChainTransfer_withCallDataAndValue() (gas: 8870454)
[PASS] test_localBalanceOf() (gas: 49223)
[PASS] test_localTotalSupply() (gas: 17234)
[PASS] test_onRead_revertForbidden() (gas: 35292)
[PASS] test_pendingNonce() (gas: 7521039)
[PASS] test_pendingTransfer() (gas: 7537762)
[PASS] test_quoteTransfer() (gas: 200882)
[PASS] test_reduce() (gas: 15816)
[PASS] test_totalSupply() (gas: 6091327)
[PASS] test_transferFrom_revertNotComposing() (gas: 85822)
[PASS] test_transfer_crossChain_basic() (gas: 8437629)
[PASS] test_transfer_crossChain_revertInsufficientBalance() (gas: 286186)
[PASS] test_transfer_crossChain_revertInsufficientValue() (gas: 6073563)
[PASS] test_transfer_crossChain_revertInvalidAddress() (gas: 6186490)
[PASS] test_transfer_crossChain_revertOverflow() (gas: 6189006)
[PASS] test_transfer_crossChain_revertTransferPending() (gas: 7633839)
[PASS] test_transfer_crossChain_revertZeroAmount() (gas: 6188940)
[PASS] test_transfer_crossChain_withCallData() (gas: 8789683)
[PASS] test_transfer_reverts_unsupported() (gas: 12748)
[PASS] test_updateGateway() (gas: 45287)
[PASS] test_updateGateway_revertNonOwner() (gas: 35426)
[PASS] test_updateLiquidityMatrix() (gas: 45363)
[PASS] test_updateLiquidityMatrix_revertNonOwner() (gas: 35454)
[PASS] test_updateReadTarget() (gas: 66540)
[PASS] test_updateReadTarget_revertNonOwner() (gas: 34324)
Suite result: ok. 44 passed; 0 failed; 0 skipped; finished in 12.29s (147.12ms CPU time)

Ran 83 tests for test/LiquidityMatrix.t.sol:LiquidityMatrixTest
[PASS] test_getAppSetting() (gas: 19029)
[PASS] test_getDataRootAt_historicalValues() (gas: 4370889)
[PASS] test_getFinalizedLiquidity() (gas: 2868886)
[PASS] test_getFinalizedRemoteDataHash() (gas: 2407033)
[PASS] test_getFinalizedRemoteLiquidity() (gas: 2413847)
[PASS] test_getFinalizedRemoteTotalLiquidity() (gas: 2418493)
[PASS] test_getFinalizedTotalLiquidity() (gas: 2863832)
[PASS] test_getLastFinalizedDataRoot() (gas: 2402540)
[PASS] test_getLastFinalizedLiquidityRoot() (gas: 2402692)
[PASS] test_getLastReceivedDataRoot() (gas: 1447625)
[PASS] test_getLastReceivedLiquidityRoot() (gas: 2775879)
[PASS] test_getLastSettledDataRoot() (gas: 1693029)
[PASS] test_getLastSettledLiquidityRoot() (gas: 1887935)
[PASS] test_getLiquidityAt() (gas: 3497306)
[PASS] test_getLiquidityRootAt() (gas: 4622240)
[PASS] test_getLocalDataHash() (gas: 402027)
[PASS] test_getLocalDataHashAt() (gas: 929283)
[PASS] test_getLocalDataRoot() (gas: 539125)
[PASS] test_getLocalLiquidity() (gas: 515893)
[PASS] test_getLocalLiquidityAt() (gas: 980602)
[PASS] test_getLocalLiquidityRoot() (gas: 643913)
[PASS] test_getLocalTotalLiquidity() (gas: 915178)
[PASS] test_getLocalTotalLiquidityAt() (gas: 1032591)
[PASS] test_getMainDataRoot() (gas: 660810)
[PASS] test_getMainLiquidityRoot() (gas: 842775)
[PASS] test_getMainRoots() (gas: 716067)
[PASS] test_getMappedAccount() (gas: 312477)
[PASS] test_getRemoteDataHashAt() (gas: 4427955)
[PASS] test_getRemoteLiquidityAt() (gas: 4829547)
[PASS] test_getRemoteTotalLiquidityAt() (gas: 6154486)
[PASS] test_getSettledLiquidity() (gas: 2342760)
[PASS] test_getSettledRemoteDataHash() (gas: 1706748)
[PASS] test_getSettledRemoteLiquidity() (gas: 2234979)
[PASS] test_getSettledRemoteTotalLiquidity() (gas: 2214900)
[PASS] test_getSettledTotalLiquidity() (gas: 2883871)
[PASS] test_getTotalLiquidityAt() (gas: 3380060)
[PASS] test_isDataSettled() (gas: 1688433)
[PASS] test_isFinalized() (gas: 785704)
[PASS] test_isFinalized(bytes32) (runs: 256, μ: 312380302, ~: 312418773)
[PASS] test_isLiquiditySettled() (gas: 1873727)
[PASS] test_isLocalAccountMapped() (gas: 321694)
[PASS] test_isSettlerWhitelisted() (gas: 95845)
[PASS] test_onReceiveMapRemoteAccountRequests_bulkMapping() (gas: 7357118)
[PASS] test_onReceiveMapRemoteAccountRequests_localAlreadyMapped() (gas: 380670)
[PASS] test_onReceiveMapRemoteAccountRequests_onlySynchronizer() (gas: 38510)
[PASS] test_onReceiveMapRemoteAccountRequests_remoteAlreadyMapped() (gas: 378486)
[PASS] test_onReceiveRoots_onlySynchronizer() (gas: 35805)
[PASS] test_onReceiveRoots_outOfOrderRoots() (gas: 361993)
[PASS] test_outOfOrderSettlement_comprehensiveChecks() (gas: 2190766)
[PASS] test_production_multiChainSettlement() (gas: 2923991)
[PASS] test_registerApp() (gas: 490806)
[PASS] test_registerApp_alreadyRegistered() (gas: 80254)
[PASS] test_registerApp_multipleAppsWithDifferentSettings() (gas: 163309)
[PASS] test_requestMapRemoteAccounts() (gas: 51623009)
[PASS] test_requestMapRemoteAccounts_invalidAddress() (gas: 50501)
[PASS] test_requestMapRemoteAccounts_invalidLengths() (gas: 51392)
[PASS] test_settleData(bytes32) (runs: 256, μ: 165506363, ~: 165506457)
[PASS] test_settleData_alreadySettled() (gas: 1709265)
[PASS] test_settleData_complexDataStructures() (gas: 2353205)
[PASS] test_settleData_notWhitelisted() (gas: 44807)
[PASS] test_settleLiquidity_alreadySettled(bytes32) (runs: 256, μ: 151613195, ~: 151654740)
[PASS] test_settleLiquidity_basic(bytes32) (runs: 256, μ: 155054479, ~: 155078876)
[PASS] test_settleLiquidity_complexScenario() (gas: 4986009)
[PASS] test_settleLiquidity_conflictingSettlements() (gas: 3784312)
[PASS] test_settleLiquidity_mixedResults() (gas: 2892458)
[PASS] test_settleLiquidity_notWhitelisted() (gas: 47722)
[PASS] test_settleLiquidity_partialSettlement() (gas: 38120581)
[PASS] test_settleLiquidity_withCallbacks(bytes32) (runs: 256, μ: 156310865, ~: 156303323)
[PASS] test_updateLocalData(bytes32) (runs: 256, μ: 137234796, ~: 137234845)
[PASS] test_updateLocalData_emptyData() (gas: 314272)
[PASS] test_updateLocalData_forbidden() (gas: 34985)
[PASS] test_updateLocalData_largeData() (gas: 421032)
[PASS] test_updateLocalData_largeDataSets() (gas: 3076682)
[PASS] test_updateLocalLiquidity(bytes32) (runs: 256, μ: 140685734, ~: 140702927)
[PASS] test_updateLocalLiquidity_forbidden() (gas: 37973)
[PASS] test_updateLocalLiquidity_highFrequencyUpdates() (gas: 4464222)
[PASS] test_updateLocalLiquidity_multipleAccountsParallel() (gas: 14808479)
[PASS] test_updateLocalLiquidity_multipleAppsAndAccounts() (gas: 4507178)
[PASS] test_updateLocalLiquidity_negativeValues() (gas: 766990)
[PASS] test_updateSettler() (gas: 41949)
[PASS] test_updateSettlerWhitelisted_onlyOwner() (gas: 33682)
[PASS] test_updateSyncMappedAccountsOnly() (gas: 41929)
[PASS] test_updateUseCallbacks() (gas: 41966)
Suite result: ok. 83 passed; 0 failed; 0 skipped; finished in 26.70s (102.53s CPU time)

╭-----------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------╮
| lib/devtools/packages/test-devtools-evm-foundry/contracts/OptionsHelper.sol:UlnOptionsMock Contract |                 |      |        |      |         |
+========================================================================================================================================================+
| Deployment Cost                                                                                     | Deployment Size |      |        |      |         |
|-----------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------|
| 379401                                                                                              | 1540            |      |        |      |         |
|-----------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------|
|                                                                                                     |                 |      |        |      |         |
|-----------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------|
| Function Name                                                                                       | Min             | Avg  | Median | Max  | # Calls |
|-----------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------|
| decode                                                                                              | 1403            | 1403 | 1403   | 1403 | 6736    |
╰-----------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------╯

╭----------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╮
| lib/devtools/packages/test-devtools-evm-foundry/contracts/mocks/DVNFeeLibMock.sol:DVNFeeLibMock Contract |                 |        |        |        |         |
+=================================================================================================================================================================+
| Deployment Cost                                                                                          | Deployment Size |        |        |        |         |
|----------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| 1342187                                                                                                  | 6228            |        |        |        |         |
|----------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                                                                          |                 |        |        |        |         |
|----------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                                                                                            | Min             | Avg    | Median | Max    | # Calls |
|----------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| getFee((address,address,uint64,uint16),(uint64,uint16,uint128),bytes,bytes)                              | 23329           | 26857  | 23329  | 38654  | 1720    |
|----------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| getFee((address,uint32,uint64,address,uint64,uint16),(uint64,uint16,uint128),bytes)                      | 11395           | 11395  | 11395  | 11395  | 2       |
|----------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| setCmdFees                                                                                               | 46195           | 46195  | 46195  | 46195  | 1249    |
|----------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| setSupportedCmdTypes                                                                                     | 94142           | 184426 | 206907 | 206907 | 1249    |
╰----------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╯

╭----------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╮
| lib/devtools/packages/test-devtools-evm-foundry/contracts/mocks/DVNMock.sol:DVNMock Contract |                 |        |        |        |         |
+=====================================================================================================================================================+
| Deployment Cost                                                                              | Deployment Size |        |        |        |         |
|----------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| 3333858                                                                                      | 16475           |        |        |        |         |
|----------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                                                              |                 |        |        |        |         |
|----------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                                                                                | Min             | Avg    | Median | Max    | # Calls |
|----------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| getFee(address,bytes,bytes,bytes)                                                            | 38385           | 41925  | 38385  | 53796  | 1720    |
|----------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| getFee(uint32,uint64,address,bytes)                                                          | 26101           | 26101  | 26101  | 26101  | 2       |
|----------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| hashCallData                                                                                 | 869             | 880    | 881    | 881    | 3368    |
|----------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| setDstConfig                                                                                 | 103097          | 200876 | 225224 | 225224 | 1249    |
|----------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| setWorkerFeeLib                                                                              | 30070           | 30080  | 30082  | 30082  | 1249    |
╰----------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╯

╭------------------------------------------------------------------------------------------------------------+-----------------+-------+--------+--------+---------╮
| lib/devtools/packages/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol:EndpointV2Mock Contract |                 |       |        |        |         |
+==================================================================================================================================================================+
| Deployment Cost                                                                                            | Deployment Size |       |        |        |         |
|------------------------------------------------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| 4426127                                                                                                    | 20427           |       |        |        |         |
|------------------------------------------------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
|                                                                                                            |                 |       |        |        |         |
|------------------------------------------------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| Function Name                                                                                              | Min             | Avg   | Median | Max    | # Calls |
|------------------------------------------------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| eid                                                                                                        | 276             | 276   | 276    | 276    | 17160   |
|------------------------------------------------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| getReceiveLibrary                                                                                          | 4885            | 4885  | 4885   | 4885   | 1684    |
|------------------------------------------------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| quote                                                                                                      | 84705           | 95936 | 92359  | 108120 | 1722    |
|------------------------------------------------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| registerLibrary                                                                                            | 77471           | 77486 | 77483  | 77495  | 3747    |
|------------------------------------------------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| setDefaultReceiveLibrary                                                                                   | 61887           | 61895 | 61887  | 61948  | 8747    |
|------------------------------------------------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| setDefaultSendLibrary                                                                                      | 55635           | 55655 | 55647  | 55712  | 8747    |
╰------------------------------------------------------------------------------------------------------------+-----------------+-------+--------+--------+---------╯

╭--------------------------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------╮
| lib/devtools/packages/test-devtools-evm-foundry/contracts/mocks/ExecutorFeeLibMock.sol:ExecutorFeeLibMock Contract |                 |      |        |      |         |
+=======================================================================================================================================================================+
| Deployment Cost                                                                                                    | Deployment Size |      |        |      |         |
|--------------------------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------|
| 1002553                                                                                                            | 4628            |      |        |      |         |
|--------------------------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------|
|                                                                                                                    |                 |      |        |      |         |
|--------------------------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------|
| Function Name                                                                                                      | Min             | Avg  | Median | Max  | # Calls |
|--------------------------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------|
| getFee((address,address,uint16),(uint64,uint16,uint128,uint128,uint64),bytes)                                      | 4148            | 4148 | 4148   | 4148 | 1720    |
|--------------------------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------|
| getFee((address,uint32,address,uint256,uint16),(uint64,uint16,uint128,uint128,uint64),bytes)                       | 4043            | 4043 | 4043   | 4043 | 2       |
╰--------------------------------------------------------------------------------------------------------------------+-----------------+------+--------+------+---------╯

╭--------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╮
| lib/devtools/packages/test-devtools-evm-foundry/contracts/mocks/ExecutorMock.sol:ExecutorMock Contract |                 |        |        |        |         |
+===============================================================================================================================================================+
| Deployment Cost                                                                                        | Deployment Size |        |        |        |         |
|--------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| 2815171                                                                                                | 13789           |        |        |        |         |
|--------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                                                                        |                 |        |        |        |         |
|--------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                                                                                          | Min             | Avg    | Median | Max    | # Calls |
|--------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| getFee(address,bytes)                                                                                  | 20859           | 20859  | 20859  | 20859  | 1720    |
|--------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| getFee(uint32,address,uint256,bytes)                                                                   | 18839           | 18839  | 18839  | 18839  | 2       |
|--------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| setDstConfig                                                                                           | 177021          | 368744 | 416484 | 416484 | 1249    |
|--------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| setWorkerFeeLib                                                                                        | 30043           | 30053  | 30055  | 30055  | 1249    |
╰--------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╯

╭----------------------------------------------------------------------------------------------------------+-----------------+-------+--------+-------+---------╮
| lib/devtools/packages/test-devtools-evm-foundry/contracts/mocks/PriceFeedMock.sol:PriceFeedMock Contract |                 |       |        |       |         |
+===============================================================================================================================================================+
| Deployment Cost                                                                                          | Deployment Size |       |        |       |         |
|----------------------------------------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| 1315749                                                                                                  | 5831            |       |        |       |         |
|----------------------------------------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                                                                          |                 |       |        |       |         |
|----------------------------------------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                                                                                            | Min             | Avg   | Median | Max   | # Calls |
|----------------------------------------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| estimateFeeByEid                                                                                         | 1387            | 4387  | 4387   | 7387  | 6842    |
|----------------------------------------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| getPriceRatioDenominator                                                                                 | 2342            | 2342  | 2342   | 2342  | 7498    |
|----------------------------------------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| setNativeTokenPriceUSD                                                                                   | 25859           | 25936 | 25859  | 28659 | 7498    |
|----------------------------------------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| setPrice                                                                                                 | 27271           | 30585 | 27271  | 47171 | 7498    |
╰----------------------------------------------------------------------------------------------------------+-----------------+-------+--------+-------+---------╯

╭--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╮
| lib/devtools/packages/test-devtools-evm-foundry/contracts/mocks/ReadLib1002Mock.sol:ReadLib1002Mock Contract |                 |        |        |        |         |
+=====================================================================================================================================================================+
| Deployment Cost                                                                                              | Deployment Size |        |        |        |         |
|--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| 4125523                                                                                                      | 19163           |        |        |        |         |
|--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                                                                              |                 |        |        |        |         |
|--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                                                                                                | Min             | Avg    | Median | Max    | # Calls |
|--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| getConfig                                                                                                    | 10731           | 10731  | 10731  | 10731  | 1682    |
|--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| isSupportedEid                                                                                               | 2496            | 2496   | 2496   | 2496   | 2498    |
|--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| messageLibType                                                                                               | 230             | 230    | 230    | 230    | 2498    |
|--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| quote                                                                                                        | 80513           | 84078  | 80513  | 96100  | 1720    |
|--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| setDefaultReadLibConfigs                                                                                     | 103497          | 103506 | 103509 | 103509 | 1249    |
|--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| supportsInterface                                                                                            | 275             | 275    | 275    | 275    | 1249    |
|--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| version                                                                                                      | 264             | 264    | 264    | 264    | 1682    |
╰--------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╯

╭------------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╮
| lib/devtools/packages/test-devtools-evm-foundry/contracts/mocks/ReceiveUln302Mock.sol:ReceiveUln302Mock Contract |                 |        |        |        |         |
+=========================================================================================================================================================================+
| Deployment Cost                                                                                                  | Deployment Size |        |        |        |         |
|------------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| 2022330                                                                                                          | 9437            |        |        |        |         |
|------------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                                                                                  |                 |        |        |        |         |
|------------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                                                                                                    | Min             | Avg    | Median | Max    | # Calls |
|------------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| getConfig                                                                                                        | 10670           | 10670  | 10670  | 10670  | 2       |
|------------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| isSupportedEid                                                                                                   | 2455            | 2455   | 2455   | 2455   | 7498    |
|------------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| messageLibType                                                                                                   | 234             | 234    | 234    | 234    | 7498    |
|------------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| setDefaultUlnConfigs                                                                                             | 103205          | 103215 | 103217 | 103217 | 7498    |
|------------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| supportsInterface                                                                                                | 263             | 263    | 263    | 263    | 1249    |
|------------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| version                                                                                                          | 245             | 245    | 245    | 245    | 2       |
╰------------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╯

╭------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╮
| lib/devtools/packages/test-devtools-evm-foundry/contracts/mocks/SendUln302Mock.sol:SendUln302Mock Contract |                 |        |        |        |         |
+===================================================================================================================================================================+
| Deployment Cost                                                                                            | Deployment Size |        |        |        |         |
|------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| 4021255                                                                                                    | 18666           |        |        |        |         |
|------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                                                                            |                 |        |        |        |         |
|------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                                                                                              | Min             | Avg    | Median | Max    | # Calls |
|------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| isSupportedEid                                                                                             | 2475            | 2475   | 2475   | 2475   | 7498    |
|------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| messageLibType                                                                                             | 210             | 210    | 210    | 210    | 7498    |
|------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| quote                                                                                                      | 70003           | 70003  | 70003  | 70003  | 2       |
|------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| setDefaultExecutorConfigs                                                                                  | 49229           | 49239  | 49241  | 49241  | 7498    |
|------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| setDefaultUlnConfigs                                                                                       | 103178          | 103188 | 103190 | 103190 | 7498    |
|------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| supportsInterface                                                                                          | 263             | 263    | 263    | 263    | 1249    |
╰------------------------------------------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╯

╭---------------------------------------------------------------------------------------------------------------------------+-----------------+-----+--------+-----+---------╮
| lib/layerzero-v2/packages/layerzero-v2/evm/protocol/contracts/messagelib/BlockedMessageLib.sol:BlockedMessageLib Contract |                 |     |        |     |         |
+============================================================================================================================================================================+
| Deployment Cost                                                                                                           | Deployment Size |     |        |     |         |
|---------------------------------------------------------------------------------------------------------------------------+-----------------+-----+--------+-----+---------|
| 0                                                                                                                         | 391             |     |        |     |         |
|---------------------------------------------------------------------------------------------------------------------------+-----------------+-----+--------+-----+---------|
|                                                                                                                           |                 |     |        |     |         |
|---------------------------------------------------------------------------------------------------------------------------+-----------------+-----+--------+-----+---------|
| Function Name                                                                                                             | Min             | Avg | Median | Max | # Calls |
|---------------------------------------------------------------------------------------------------------------------------+-----------------+-----+--------+-----+---------|
| supportsInterface                                                                                                         | 229             | 229 | 229    | 229 | 1249    |
╰---------------------------------------------------------------------------------------------------------------------------+-----------------+-----+--------+-----+---------╯

╭-----------------------------------------------+-----------------+---------+---------+---------+---------╮
| src/ERC20xD.sol:ERC20xD Contract              |                 |         |         |         |         |
+=========================================================================================================+
| Deployment Cost                               | Deployment Size |         |         |         |         |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| 0                                             | 19641           |         |         |         |         |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
|                                               |                 |         |         |         |         |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| Function Name                                 | Min             | Avg     | Median  | Max     | # Calls |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| addHook                                       | 74699           | 91606   | 91799   | 91799   | 89      |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| approve                                       | 46024           | 46024   | 46024   | 46024   | 2       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| availableLocalBalanceOf                       | 18886           | 38747   | 40318   | 42423   | 319     |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| balanceOf                                     | 31324           | 87815   | 91756   | 91756   | 320     |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| burn                                          | 67015           | 1111496 | 1348019 | 1348019 | 11      |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| cancelPendingTransfer                         | 27799           | 33409   | 33409   | 39019   | 4       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| decimals                                      | 280             | 280     | 280     | 280     | 1       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| gateway                                       | 2368            | 2368    | 2368    | 2368    | 2       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| liquidityMatrix                               | 2382            | 2382    | 2382    | 2382    | 2       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| localBalanceOf                                | 1845            | 10936   | 12345   | 12345   | 343     |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| localTotalSupply                              | 12087           | 12087   | 12087   | 12087   | 7       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| mint                                          | 24115           | 203118  | 109288  | 459466  | 3590    |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| name                                          | 2747            | 2747    | 2747    | 2747    | 1       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| onRead                                        | 24764           | 24840   | 24840   | 24916   | 2       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| owner                                         | 2365            | 2365    | 2365    | 2365    | 1       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| pendingNonce                                  | 2465            | 2465    | 2465    | 2465    | 18      |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| pendingTransfer                               | 23032           | 23032   | 23032   | 23032   | 4       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| quoteBurn                                     | 193655          | 193655  | 193655  | 193655  | 11      |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| quoteTransfer                                 | 193643          | 193643  | 193643  | 193643  | 62      |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| reduce                                        | 683             | 2843    | 2919    | 2919    | 48      |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| symbol                                        | 2758            | 2758    | 2758    | 2758    | 1       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| totalSupply                                   | 44112           | 65012   | 44112   | 91138   | 9       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| transfer(address,uint256)                     | 317             | 317     | 317     | 317     | 1       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| transfer(address,uint256,bytes)               | 24040           | 873191  | 1347286 | 1368254 | 43      |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| transfer(address,uint256,bytes,uint256,bytes) | 114931          | 1208756 | 1433602 | 1476147 | 18      |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| transferFrom                                  | 24438           | 24438   | 24438   | 24438   | 2       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| updateGateway                                 | 23844           | 26927   | 26927   | 30011   | 2       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| updateLiquidityMatrix                         | 23866           | 26955   | 26955   | 30044   | 2       |
|-----------------------------------------------+-----------------+---------+---------+---------+---------|
| updateReadTarget                              | 23714           | 55439   | 55447   | 55459   | 5266    |
╰-----------------------------------------------+-----------------+---------+---------+---------+---------╯

╭--------------------------------------------------+-----------------+----------+----------+----------+---------╮
| src/LiquidityMatrix.sol:LiquidityMatrix Contract |                 |          |          |          |         |
+===============================================================================================================+
| Deployment Cost                                  | Deployment Size |          |          |          |         |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| 0                                                | 26016           |          |          |          |         |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
|                                                  |                 |          |          |          |         |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| Function Name                                    | Min             | Avg      | Median   | Max      | # Calls |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| gateway                                          | 2374            | 2374     | 2374     | 2374     | 1629    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getAppSetting                                    | 2519            | 2519     | 2519     | 2519     | 12      |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getDataRootAt                                    | 2557            | 2557     | 2557     | 2557     | 9       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getFinalizedLiquidity                            | 22769           | 25027    | 22769    | 29545    | 3       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getFinalizedRemoteDataHash                       | 2559            | 5959     | 5959     | 9359     | 2       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getFinalizedRemoteLiquidity                      | 2654            | 7156     | 7156     | 11659    | 2       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getFinalizedRemoteTotalLiquidity                 | 2628            | 5586     | 2628     | 11504    | 3       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getFinalizedTotalLiquidity                       | 22680           | 24919    | 22680    | 29398    | 3       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLastFinalizedDataRoot                         | 2561            | 3449     | 2561     | 4781     | 5       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLastFinalizedLiquidityRoot                    | 2649            | 3388     | 2649     | 4868     | 9       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLastReceivedDataRoot                          | 2476            | 7082     | 7084     | 7084     | 3717    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLastReceivedLiquidityRoot                     | 2503            | 7098     | 7099     | 7099     | 6617    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLastSettledDataRoot                           | 2572            | 3682     | 3682     | 4792     | 6       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLastSettledLiquidityRoot                      | 2648            | 4034     | 4867     | 4867     | 8       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLiquidityAt                                   | 18694           | 25059    | 24224    | 30449    | 16      |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLiquidityRootAt                               | 2546            | 2546     | 2546     | 2546     | 11      |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLocalDataHash                                 | 2685            | 7050     | 7051     | 7051     | 196623  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLocalDataHashAt                               | 2664            | 7030     | 7030     | 14112    | 196623  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLocalDataRoot                                 | 2481            | 2481     | 2481     | 2481     | 196611  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLocalLiquidity                                | 723             | 7021     | 7089     | 7089     | 389819  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLocalLiquidityAt                              | 7134            | 10882    | 11855    | 18923    | 327689  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLocalLiquidityRoot                            | 2495            | 2495     | 2495     | 2495     | 327683  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLocalTotalLiquidity                           | 2614            | 6979     | 6980     | 6980     | 327699  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getLocalTotalLiquidityAt                         | 7007            | 28089    | 28180    | 28276    | 327689  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getMainDataRoot                                  | 2385            | 2385     | 2385     | 2385     | 196611  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getMainLiquidityRoot                             | 2374            | 2374     | 2374     | 2374     | 327683  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getMainRoots                                     | 4491            | 15018    | 4491     | 25555    | 6895    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getMappedAccount                                 | 2738            | 2738     | 2738     | 2738     | 252     |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getRemoteDataHashAt                              | 7085            | 9042     | 7088     | 12146    | 5       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getRemoteLiquidityAt                             | 7118            | 11028    | 11836    | 12176    | 5       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getRemoteTotalLiquidityAt                        | 7061            | 8950     | 7064     | 11782    | 5       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getSettledLiquidity                              | 10576           | 75282    | 86508    | 86508    | 424     |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getSettledRemoteDataHash                         | 2543            | 9341     | 9342     | 9342     | 65542   |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getSettledRemoteLiquidity                        | 11696           | 11696    | 11696    | 11696    | 23764   |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getSettledRemoteTotalLiquidity                   | 2671            | 11489    | 11558    | 11558    | 261     |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getSettledTotalLiquidity                         | 22694           | 48531    | 38994    | 86020    | 15      |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| getTotalLiquidityAt                              | 18483           | 25038    | 26206    | 27907    | 10      |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| isDataSettled                                    | 2691            | 2691     | 2691     | 2691     | 267     |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| isFinalized                                      | 2610            | 4040     | 4775     | 4775     | 790     |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| isLiquiditySettled                               | 2672            | 2672     | 2672     | 2672     | 270     |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| isLocalAccountMapped                             | 2712            | 2712     | 2712     | 2712     | 53      |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| isSettlerWhitelisted                             | 2476            | 2476     | 2476     | 2476     | 3       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| onReceiveMapRemoteAccountRequests                | 24603           | 732571   | 220436   | 4877500  | 8       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| onReceiveRoots                                   | 24023           | 98258    | 101695   | 116042   | 9       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| quoteRequestMapRemoteAccounts                    | 146365          | 146365   | 146365   | 146365   | 2       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| quoteSync                                        | 131991          | 143284   | 131991   | 192632   | 1627    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| reduce                                           | 2986            | 3918     | 2986     | 7988     | 1627    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| registerApp                                      | 23990           | 46091    | 46174    | 46438    | 261     |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| requestMapRemoteAccounts                         | 27695           | 2706011  | 2697617  | 5401116  | 4       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| setGateway                                       | 47119           | 47141    | 47143    | 47143    | 1249    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| setSyncer                                        | 47168           | 47178    | 47180    | 47180    | 1249    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| settleData                                       | 29581           | 22432621 | 23335972 | 23356211 | 533     |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| settleLiquidity                                  | 28593           | 3223241  | 458160   | 12047020 | 3435    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| sync                                             | 565299          | 690336   | 650799   | 868972   | 1627    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| updateLocalData                                  | 25125           | 252942   | 245439   | 371064   | 196656  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| updateLocalLiquidity                             | 24124           | 282612   | 264637   | 423782   | 328035  |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| updateReadTarget                                 | 55422           | 55443    | 55446    | 55446    | 7498    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| updateSettler                                    | 28154           | 28154    | 28154    | 28154    | 1       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| updateSettlerWhitelisted                         | 23830           | 47653    | 47674    | 47674    | 2317    |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| updateSyncMappedAccountsOnly                     | 28172           | 28172    | 28172    | 28172    | 1       |
|--------------------------------------------------+-----------------+----------+----------+----------+---------|
| updateUseCallbacks                               | 28189           | 28189    | 28189    | 28189    | 257     |
╰--------------------------------------------------+-----------------+----------+----------+----------+---------╯

╭------------------------------------+-----------------+--------+---------+---------+---------╮
| src/NativexD.sol:NativexD Contract |                 |        |         |         |         |
+=============================================================================================+
| Deployment Cost                    | Deployment Size |        |         |         |         |
|------------------------------------+-----------------+--------+---------+---------+---------|
| 0                                  | 20051           |        |         |         |         |
|------------------------------------+-----------------+--------+---------+---------+---------|
|                                    |                 |        |         |         |         |
|------------------------------------+-----------------+--------+---------+---------+---------|
| Function Name                      | Min             | Avg    | Median  | Max     | # Calls |
|------------------------------------+-----------------+--------+---------+---------+---------|
| balanceOf                          | 39981           | 43619  | 44347   | 44347   | 6       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| decimals                           | 241             | 241    | 241     | 241     | 1       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| fallback                           | 21080           | 21080  | 21080   | 21080   | 1       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| name                               | 2766            | 2766   | 2766    | 2766    | 1       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| owner                              | 2343            | 2343   | 2343    | 2343    | 1       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| quoteTransfer                      | 193557          | 193557 | 193557  | 193557  | 3       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| quoteUnwrap                        | 193527          | 193527 | 193527  | 193527  | 1       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| quoteWrap                          | 271             | 271    | 271     | 271     | 2       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| receive                            | 21040           | 21040  | 21040   | 21040   | 1       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| symbol                             | 2785            | 2785   | 2785    | 2785    | 1       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| totalSupply                        | 44128           | 44128  | 44128   | 44128   | 1       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| underlying                         | 277             | 277    | 277     | 277     | 1       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| unwrap                             | 27334           | 938658 | 1394321 | 1394321 | 3       |
|------------------------------------+-----------------+--------+---------+---------+---------|
| updateReadTarget                   | 55469           | 55469  | 55469   | 55469   | 784     |
|------------------------------------+-----------------+--------+---------+---------+---------|
| wrap                               | 26492           | 270814 | 398481  | 398481  | 10      |
╰------------------------------------+-----------------+--------+---------+---------+---------╯

╭------------------------------------------------+-----------------+---------+---------+---------+---------╮
| src/WrappedERC20xD.sol:WrappedERC20xD Contract |                 |         |         |         |         |
+==========================================================================================================+
| Deployment Cost                                | Deployment Size |         |         |         |         |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| 0                                              | 20319           |         |         |         |         |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
|                                                |                 |         |         |         |         |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| Function Name                                  | Min             | Avg     | Median  | Max     | # Calls |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| addHook                                        | 74721           | 91429   | 91821   | 91821   | 131     |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| availableLocalBalanceOf                        | 35975           | 35975   | 35975   | 35975   | 49      |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| balanceOf                                      | 7807            | 28487   | 44362   | 44362   | 21      |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| decimals                                       | 280             | 280     | 280     | 280     | 1       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| fallback                                       | 21080           | 21080   | 21080   | 21080   | 1       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| getHooks                                       | 2619            | 4638    | 4891    | 4891    | 9       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| isHook                                         | 2460            | 2460    | 2460    | 2460    | 9       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| localBalanceOf                                 | 7979            | 11981   | 12345   | 12345   | 12      |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| name                                           | 2747            | 2747    | 2747    | 2747    | 1       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| onRead                                         | 64707           | 97929   | 88921   | 177073  | 10      |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| owner                                          | 2381            | 2381    | 2381    | 2381    | 1       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| quoteTransfer                                  | 6056            | 104760  | 193594  | 193594  | 19      |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| quoteUnwrap                                    | 193568          | 193568  | 193568  | 193568  | 1       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| quoteWrap                                      | 298             | 298     | 298     | 298     | 2       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| receive                                        | 21040           | 21040   | 21040   | 21040   | 1       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| reduce                                         | 2905            | 2905    | 2905    | 2905    | 7       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| removeHook                                     | 32677           | 32677   | 32677   | 32677   | 1       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| symbol                                         | 2758            | 2758    | 2758    | 2758    | 1       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| totalSupply                                    | 44108           | 44108   | 44108   | 44108   | 1       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| transfer                                       | 1374459         | 1374459 | 1374459 | 1374459 | 3       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| underlying                                     | 265             | 265     | 265     | 265     | 9       |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| unwrap                                         | 27312           | 574150  | 184266  | 1400537 | 18      |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| updateReadTarget                               | 51268           | 55422   | 55449   | 55449   | 1577    |
|------------------------------------------------+-----------------+---------+---------+---------+---------|
| wrap                                           | 26725           | 326422  | 433118  | 548636  | 32      |
╰------------------------------------------------+-----------------+---------+---------+---------+---------╯

╭-------------------------------------------------------------+-----------------+--------+--------+--------+---------╮
| src/gateways/LayerZeroGateway.sol:LayerZeroGateway Contract |                 |        |        |        |         |
+====================================================================================================================+
| Deployment Cost                                             | Deployment Size |        |        |        |         |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| 0                                                           | 17165           |        |        |        |         |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                             |                 |        |        |        |         |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                                               | Min             | Avg    | Median | Max    | # Calls |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| allowInitializePath                                         | 2456            | 2456   | 2456   | 2456   | 1638    |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| chainUIDAt                                                  | 561             | 865    | 561    | 2561   | 3087    |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| chainUIDsLength                                             | 336             | 2331   | 2336   | 2336   | 471     |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| configChains                                                | 75581           | 89514  | 92984  | 92984  | 1249    |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| endpoint                                                    | 247             | 247    | 247    | 247    | 7498    |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| quoteRead                                                   | 126728          | 140726 | 126728 | 188060 | 1720    |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| quoteSendMessage                                            | 98990           | 98990  | 98990  | 98990  | 2       |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| registerApp                                                 | 52595           | 61424  | 69695  | 69719  | 2425    |
|-------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| setPeer                                                     | 47515           | 47537  | 47539  | 47539  | 7498    |
╰-------------------------------------------------------------+-----------------+--------+--------+--------+---------╯

╭------------------------------------------------------------------------+-----------------+--------+---------+---------+---------╮
| src/hooks/DividendDistributorHook.sol:DividendDistributorHook Contract |                 |        |         |         |         |
+=================================================================================================================================+
| Deployment Cost                                                        | Deployment Size |        |         |         |         |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| 0                                                                      | 8584            |        |         |         |         |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
|                                                                        |                 |        |         |         |         |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| Function Name                                                          | Min             | Avg    | Median  | Max     | # Calls |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| balanceOf                                                              | 2472            | 2472   | 2472    | 2472    | 6       |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| cumulativeDividendsPerShare                                            | 2352            | 2352   | 2352    | 2352    | 1       |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| emergencyWithdraw                                                      | 25180           | 677770 | 677770  | 1330360 | 2       |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| getDividendBalance                                                     | 47332           | 47332  | 47332   | 47332   | 1       |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| pendingDividends                                                       | 4695            | 20120  | 26127   | 26127   | 32      |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| quoteRequestClaimDividends                                             | 193335          | 193335 | 193335  | 193335  | 5       |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| quoteTransferDividends                                                 | 196670          | 196670 | 196670  | 196670  | 5       |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| reduce                                                                 | 11219           | 11219  | 11219   | 11219   | 3       |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| registerForDividends                                                   | 50195           | 50203  | 50207   | 50207   | 264     |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| requestClaimDividends                                                  | 28209           | 812267 | 1151457 | 1254990 | 6       |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| totalDividendsDistributed                                              | 2347            | 2347   | 2347    | 2347    | 2       |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| totalSupply                                                            | 2369            | 2369   | 2369    | 2369    | 2       |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| unclaimedDividends                                                     | 2437            | 2437   | 2437    | 2437    | 2       |
|------------------------------------------------------------------------+-----------------+--------+---------+---------+---------|
| updateReadTarget                                                       | 55451           | 55451  | 55451   | 55451   | 616     |
╰------------------------------------------------------------------------+-----------------+--------+---------+---------+---------╯

╭------------------------------------------------+-----------------+-------+--------+-------+---------╮
| src/hooks/ERC7540Hook.sol:ERC7540Hook Contract |                 |       |        |       |         |
+=====================================================================================================+
| Deployment Cost                                | Deployment Size |       |        |       |         |
|------------------------------------------------+-----------------+-------+--------+-------+---------|
| 0                                              | 3947            |       |        |       |         |
|------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                |                 |       |        |       |         |
|------------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                                  | Min             | Avg   | Median | Max   | # Calls |
|------------------------------------------------+-----------------+-------+--------+-------+---------|
| asset                                          | 207             | 207   | 207    | 207   | 8       |
|------------------------------------------------+-----------------+-------+--------+-------+---------|
| claimableDepositRequest                        | 14082           | 14082 | 14082  | 14082 | 2       |
|------------------------------------------------+-----------------+-------+--------+-------+---------|
| claimableRedeemRequest                         | 14105           | 14105 | 14105  | 14105 | 2       |
|------------------------------------------------+-----------------+-------+--------+-------+---------|
| depositAssets                                  | 54126           | 54126 | 54126  | 54126 | 1       |
|------------------------------------------------+-----------------+-------+--------+-------+---------|
| pendingDepositRequest                          | 14078           | 14078 | 14078  | 14078 | 1       |
|------------------------------------------------+-----------------+-------+--------+-------+---------|
| pendingRedeemRequest                           | 14080           | 14080 | 14080  | 14080 | 1       |
|------------------------------------------------+-----------------+-------+--------+-------+---------|
| token                                          | 237             | 237   | 237    | 237   | 8       |
|------------------------------------------------+-----------------+-------+--------+-------+---------|
| vault                                          | 220             | 220   | 220    | 220   | 8       |
╰------------------------------------------------+-----------------+-------+--------+-------+---------╯

╭-----------------------------------------+-----------------+--------+--------+--------+---------╮
| test/ERC20xD.t.sol:ERC20xDTest Contract |                 |        |        |        |         |
+================================================================================================+
| Deployment Cost                         | Deployment Size |        |        |        |         |
|-----------------------------------------+-----------------+--------+--------+--------+---------|
| 44081607                                | 218996          |        |        |        |         |
|-----------------------------------------+-----------------+--------+--------+--------+---------|
|                                         |                 |        |        |        |         |
|-----------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                           | Min             | Avg    | Median | Max    | # Calls |
|-----------------------------------------+-----------------+--------+--------+--------+---------|
| assertGuid                              | 412             | 412    | 412    | 412    | 282     |
|-----------------------------------------+-----------------+--------+--------+--------+---------|
| decodeLzReadOption                      | 584             | 592    | 584    | 608    | 846     |
|-----------------------------------------+-----------------+--------+--------+--------+---------|
| nextExecutorOption                      | 743             | 743    | 743    | 743    | 1128    |
|-----------------------------------------+-----------------+--------+--------+--------+---------|
| verifyPackets                           | 376544          | 749701 | 759903 | 872294 | 282     |
╰-----------------------------------------+-----------------+--------+--------+--------+---------╯

╭---------------------------------------------------------+-----------------+----------+----------+----------+---------╮
| test/LiquidityMatrix.t.sol:LiquidityMatrixTest Contract |                 |          |          |          |         |
+======================================================================================================================+
| Deployment Cost                                         | Deployment Size |          |          |          |         |
|---------------------------------------------------------+-----------------+----------+----------+----------+---------|
| 67338469                                                | 335017          |          |          |          |         |
|---------------------------------------------------------+-----------------+----------+----------+----------+---------|
|                                                         |                 |          |          |          |         |
|---------------------------------------------------------+-----------------+----------+----------+----------+---------|
| Function Name                                           | Min             | Avg      | Median   | Max      | # Calls |
|---------------------------------------------------------+-----------------+----------+----------+----------+---------|
| assertGuid                                              | 451             | 451      | 451      | 451      | 1326    |
|---------------------------------------------------------+-----------------+----------+----------+----------+---------|
| decodeLzReadOption                                      | 616             | 623      | 616      | 639      | 3972    |
|---------------------------------------------------------+-----------------+----------+----------+----------+---------|
| decodeLzReceiveOption                                   | 573             | 580      | 573      | 596      | 6       |
|---------------------------------------------------------+-----------------+----------+----------+----------+---------|
| nextExecutorOption                                      | 768             | 768      | 768      | 768      | 5304    |
|---------------------------------------------------------+-----------------+----------+----------+----------+---------|
| verifyPackets(uint32,bytes32)                           | 12801070        | 12801076 | 12801076 | 12801082 | 2       |
|---------------------------------------------------------+-----------------+----------+----------+----------+---------|
| verifyPackets(uint32,bytes32,uint256,address,bytes)     | 269551          | 305680   | 301895   | 375706   | 1324    |
╰---------------------------------------------------------+-----------------+----------+----------+----------+---------╯

╭--------------------------------------------------------+-----------------+------+--------+------+---------╮
| test/WrappedERC20xD.hooks.t.sol:DataUsingHook Contract |                 |      |        |      |         |
+===========================================================================================================+
| Deployment Cost                                        | Deployment Size |      |        |      |         |
|--------------------------------------------------------+-----------------+------+--------+------+---------|
| 399585                                                 | 1637            |      |        |      |         |
|--------------------------------------------------------+-----------------+------+--------+------+---------|
|                                                        |                 |      |        |      |         |
|--------------------------------------------------------+-----------------+------+--------+------+---------|
| Function Name                                          | Min             | Avg  | Median | Max  | # Calls |
|--------------------------------------------------------+-----------------+------+--------+------+---------|
| lastGasLimit                                           | 2322            | 2322 | 2322   | 2322 | 1       |
|--------------------------------------------------------+-----------------+------+--------+------+---------|
| lastRefundTo                                           | 2312            | 2312 | 2312   | 2312 | 1       |
╰--------------------------------------------------------+-----------------+------+--------+------+---------╯

╭------------------------------------------------------------+-----------------+------+--------+------+---------╮
| test/WrappedERC20xD.hooks.t.sol:OrderTrackingHook Contract |                 |      |        |      |         |
+===============================================================================================================+
| Deployment Cost                                            | Deployment Size |      |        |      |         |
|------------------------------------------------------------+-----------------+------+--------+------+---------|
| 389614                                                     | 1601            |      |        |      |         |
|------------------------------------------------------------+-----------------+------+--------+------+---------|
|                                                            |                 |      |        |      |         |
|------------------------------------------------------------+-----------------+------+--------+------+---------|
| Function Name                                              | Min             | Avg  | Median | Max  | # Calls |
|------------------------------------------------------------+-----------------+------+--------+------+---------|
| lastAmount                                                 | 2329            | 2329 | 2329   | 2329 | 3       |
|------------------------------------------------------------+-----------------+------+--------+------+---------|
| lastFrom                                                   | 2330            | 2330 | 2330   | 2330 | 3       |
|------------------------------------------------------------+-----------------+------+--------+------+---------|
| lastTo                                                     | 2336            | 2336 | 2336   | 2336 | 3       |
╰------------------------------------------------------------+-----------------+------+--------+------+---------╯

╭------------------------------------------------------------------+-----------------+-------+--------+-------+---------╮
| test/WrappedERC20xD.hooks.t.sol:RecipientRedemptionHook Contract |                 |       |        |       |         |
+=======================================================================================================================+
| Deployment Cost                                                  | Deployment Size |       |        |       |         |
|------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| 480974                                                           | 2170            |       |        |       |         |
|------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                                  |                 |       |        |       |         |
|------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                                                    | Min             | Avg   | Median | Max   | # Calls |
|------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| setRecipientOverride                                             | 43767           | 43767 | 43767  | 43767 | 1       |
╰------------------------------------------------------------------+-----------------+-------+--------+-------+---------╯

╭-------------------------------------------------------------------------------+-----------------+--------+--------+---------+---------╮
| test/hooks/DividendDistributorHook.t.sol:DividendDistributorHookTest Contract |                 |        |        |         |         |
+=======================================================================================================================================+
| Deployment Cost                                                               | Deployment Size |        |        |         |         |
|-------------------------------------------------------------------------------+-----------------+--------+--------+---------+---------|
| 42688723                                                                      | 213398          |        |        |         |         |
|-------------------------------------------------------------------------------+-----------------+--------+--------+---------+---------|
|                                                                               |                 |        |        |         |         |
|-------------------------------------------------------------------------------+-----------------+--------+--------+---------+---------|
| Function Name                                                                 | Min             | Avg    | Median | Max     | # Calls |
|-------------------------------------------------------------------------------+-----------------+--------+--------+---------+---------|
| assertGuid                                                                    | 426             | 426    | 426    | 426     | 17      |
|-------------------------------------------------------------------------------+-----------------+--------+--------+---------+---------|
| decodeLzReadOption                                                            | 567             | 574    | 567    | 590     | 51      |
|-------------------------------------------------------------------------------+-----------------+--------+--------+---------+---------|
| nextExecutorOption                                                            | 721             | 721    | 721    | 721     | 68      |
|-------------------------------------------------------------------------------+-----------------+--------+--------+---------+---------|
| verifyPackets                                                                 | 480945          | 849202 | 836816 | 1566166 | 17      |
╰-------------------------------------------------------------------------------+-----------------+--------+--------+---------+---------╯

╭-------------------------------------------------------+-----------------+--------+--------+--------+---------╮
| test/hooks/ERC7540Hook.t.sol:ERC7540HookTest Contract |                 |        |        |        |         |
+==============================================================================================================+
| Deployment Cost                                       | Deployment Size |        |        |        |         |
|-------------------------------------------------------+-----------------+--------+--------+--------+---------|
| 44609445                                              | 222040          |        |        |        |         |
|-------------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                       |                 |        |        |        |         |
|-------------------------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                                         | Min             | Avg    | Median | Max    | # Calls |
|-------------------------------------------------------+-----------------+--------+--------+--------+---------|
| assertGuid                                            | 411             | 411    | 411    | 411    | 7       |
|-------------------------------------------------------+-----------------+--------+--------+--------+---------|
| decodeLzReadOption                                    | 569             | 576    | 569    | 592    | 21      |
|-------------------------------------------------------+-----------------+--------+--------+--------+---------|
| nextExecutorOption                                    | 735             | 735    | 735    | 735    | 28      |
|-------------------------------------------------------+-----------------+--------+--------+--------+---------|
| verifyPackets                                         | 469561          | 501763 | 479161 | 538300 | 7       |
╰-------------------------------------------------------+-----------------+--------+--------+--------+---------╯

╭---------------------------------------------------------+-----------------+-------+--------+-------+---------╮
| test/libraries/AddressLib.t.sol:AddressLibTest Contract |                 |       |        |       |         |
+==============================================================================================================+
| Deployment Cost                                         | Deployment Size |       |        |       |         |
|---------------------------------------------------------+-----------------+-------+--------+-------+---------|
| 2114251                                                 | 10394           |       |        |       |         |
|---------------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                         |                 |       |        |       |         |
|---------------------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                                           | Min             | Avg   | Median | Max   | # Calls |
|---------------------------------------------------------+-----------------+-------+--------+-------+---------|
| callTransferNative                                      | 56464           | 56620 | 56620  | 56776 | 2       |
|---------------------------------------------------------+-----------------+-------+--------+-------+---------|
| receive                                                 | 21059           | 21059 | 21059  | 21059 | 1       |
╰---------------------------------------------------------+-----------------+-------+--------+-------+---------╯

╭-------------------------------------------------------+-----------------+-------+--------+-------+---------╮
| test/libraries/AddressLib.t.sol:ContractMock Contract |                 |       |        |       |         |
+============================================================================================================+
| Deployment Cost                                       | Deployment Size |       |        |       |         |
|-------------------------------------------------------+-----------------+-------+--------+-------+---------|
| 87428                                                 | 189             |       |        |       |         |
|-------------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                       |                 |       |        |       |         |
|-------------------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                                         | Min             | Avg   | Median | Max   | # Calls |
|-------------------------------------------------------+-----------------+-------+--------+-------+---------|
| receive                                               | 43159           | 43159 | 43159  | 43159 | 1       |
|-------------------------------------------------------+-----------------+-------+--------+-------+---------|
| receivedAmount                                        | 2241            | 2241  | 2241   | 2241  | 1       |
╰-------------------------------------------------------+-----------------+-------+--------+-------+---------╯

╭------------------------------------------------------------+-----------------+-------+--------+-------+---------╮
| test/libraries/AddressLib.t.sol:RevertingContract Contract |                 |       |        |       |         |
+=================================================================================================================+
| Deployment Cost                                            | Deployment Size |       |        |       |         |
|------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| 87656                                                      | 191             |       |        |       |         |
|------------------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                            |                 |       |        |       |         |
|------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                                              | Min             | Avg   | Median | Max   | # Calls |
|------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| receive                                                    | 21096           | 21096 | 21096  | 21096 | 1       |
╰------------------------------------------------------------+-----------------+-------+--------+-------+---------╯

╭---------------------------------------------------------------+-----------------+------+--------+------+---------╮
| test/libraries/MerkleTreeLib.t.sol:MerkleTreeLibTest Contract |                 |      |        |      |         |
+==================================================================================================================+
| Deployment Cost                                               | Deployment Size |      |        |      |         |
|---------------------------------------------------------------+-----------------+------+--------+------+---------|
| 4139347                                                       | 20507           |      |        |      |         |
|---------------------------------------------------------------+-----------------+------+--------+------+---------|
|                                                               |                 |      |        |      |         |
|---------------------------------------------------------------+-----------------+------+--------+------+---------|
| Function Name                                                 | Min             | Avg  | Median | Max  | # Calls |
|---------------------------------------------------------------+-----------------+------+--------+------+---------|
| callComputeRoot                                               | 1240            | 1240 | 1240   | 1240 | 1       |
|---------------------------------------------------------------+-----------------+------+--------+------+---------|
| callGetProof                                                  | 1236            | 1253 | 1253   | 1271 | 2       |
╰---------------------------------------------------------------+-----------------+------+--------+------+---------╯

╭----------------------------------------------------------------+-----------------+------+--------+------+---------╮
| test/mixins/BaseERC20xD.hooks.t.sol:OrderTrackingHook Contract |                 |      |        |      |         |
+===================================================================================================================+
| Deployment Cost                                                | Deployment Size |      |        |      |         |
|----------------------------------------------------------------+-----------------+------+--------+------+---------|
| 626528                                                         | 2755            |      |        |      |         |
|----------------------------------------------------------------+-----------------+------+--------+------+---------|
|                                                                |                 |      |        |      |         |
|----------------------------------------------------------------+-----------------+------+--------+------+---------|
| Function Name                                                  | Min             | Avg  | Median | Max  | # Calls |
|----------------------------------------------------------------+-----------------+------+--------+------+---------|
| afterTransferCallOrder                                         | 2329            | 2329 | 2329   | 2329 | 6       |
|----------------------------------------------------------------+-----------------+------+--------+------+---------|
| beforeTransferCallOrder                                        | 2315            | 2315 | 2315   | 2315 | 6       |
|----------------------------------------------------------------+-----------------+------+--------+------+---------|
| onInitiateTransferCallOrder                                    | 2314            | 2314 | 2314   | 2314 | 3       |
|----------------------------------------------------------------+-----------------+------+--------+------+---------|
| onMapAccountsCallOrder                                         | 2314            | 2314 | 2314   | 2314 | 3       |
╰----------------------------------------------------------------+-----------------+------+--------+------+---------╯

╭--------------------------------------------------------+-----------------+--------+--------+--------+---------╮
| test/mixins/BaseERC20xD.t.sol:BaseERC20xDTest Contract |                 |        |        |        |         |
+===============================================================================================================+
| Deployment Cost                                        | Deployment Size |        |        |        |         |
|--------------------------------------------------------+-----------------+--------+--------+--------+---------|
| 48397047                                               | 240460          |        |        |        |         |
|--------------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                        |                 |        |        |        |         |
|--------------------------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                                          | Min             | Avg    | Median | Max    | # Calls |
|--------------------------------------------------------+-----------------+--------+--------+--------+---------|
| assertGuid                                             | 434             | 434    | 434    | 434    | 52      |
|--------------------------------------------------------+-----------------+--------+--------+--------+---------|
| decodeLzReadOption                                     | 569             | 576    | 569    | 592    | 156     |
|--------------------------------------------------------+-----------------+--------+--------+--------+---------|
| nextExecutorOption                                     | 740             | 740    | 740    | 740    | 208     |
|--------------------------------------------------------+-----------------+--------+--------+--------+---------|
| verifyPackets                                          | 357421          | 683129 | 759943 | 872334 | 52      |
╰--------------------------------------------------------+-----------------+--------+--------+--------+---------╯

╭-----------------------------------------+-----------------+-------+--------+-------+---------╮
| test/mocks/AppMock.sol:AppMock Contract |                 |       |        |       |         |
+==============================================================================================+
| Deployment Cost                         | Deployment Size |       |        |       |         |
|-----------------------------------------+-----------------+-------+--------+-------+---------|
| 400210                                  | 1775            |       |        |       |         |
|-----------------------------------------+-----------------+-------+--------+-------+---------|
|                                         |                 |       |        |       |         |
|-----------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                           | Min             | Avg   | Median | Max   | # Calls |
|-----------------------------------------+-----------------+-------+--------+-------+---------|
| remoteLiquidity                         | 2443            | 2443  | 2443   | 2443  | 23686   |
|-----------------------------------------+-----------------+-------+--------+-------+---------|
| remoteTotalLiquidity                    | 2360            | 2360  | 2360   | 2360  | 256     |
|-----------------------------------------+-----------------+-------+--------+-------+---------|
| setShouldMapAccounts                    | 44664           | 44675 | 44676  | 44676 | 231     |
|-----------------------------------------+-----------------+-------+--------+-------+---------|
| shouldMapAccounts                       | 2601            | 2601  | 2601   | 2601  | 256     |
╰-----------------------------------------+-----------------+-------+--------+-------+---------╯

╭---------------------------------------------+-----------------+-------+--------+-------+---------╮
| test/mocks/ERC20Mock.sol:ERC20Mock Contract |                 |       |        |       |         |
+==================================================================================================+
| Deployment Cost                             | Deployment Size |       |        |       |         |
|---------------------------------------------+-----------------+-------+--------+-------+---------|
| 774030                                      | 4486            |       |        |       |         |
|---------------------------------------------+-----------------+-------+--------+-------+---------|
|                                             |                 |       |        |       |         |
|---------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                               | Min             | Avg   | Median | Max   | # Calls |
|---------------------------------------------+-----------------+-------+--------+-------+---------|
| approve                                     | 28869           | 46250 | 46269  | 46269 | 1051    |
|---------------------------------------------+-----------------+-------+--------+-------+---------|
| balanceOf                                   | 2383            | 2383  | 2383   | 2383  | 28      |
|---------------------------------------------+-----------------+-------+--------+-------+---------|
| mint                                        | 50627           | 56596 | 50915  | 68015 | 1060    |
|---------------------------------------------+-----------------+-------+--------+-------+---------|
| transfer                                    | 51035           | 51035 | 51035  | 51035 | 6       |
╰---------------------------------------------+-----------------+-------+--------+-------+---------╯

╭-------------------------------------------------+-----------------+--------+--------+--------+---------╮
| test/mocks/ERC20xDMock.sol:ERC20xDMock Contract |                 |        |        |        |         |
+========================================================================================================+
| Deployment Cost                                 | Deployment Size |        |        |        |         |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| 4305783                                         | 20675           |        |        |        |         |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                 |                 |        |        |        |         |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                                   | Min             | Avg    | Median | Max    | # Calls |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| addHook                                         | 23615           | 82405  | 91800  | 91800  | 67      |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| getHooks                                        | 2619            | 6274   | 7188   | 9485   | 5       |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| isHook                                          | 2460            | 2460   | 2460   | 2460   | 2       |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| localBalanceOf                                  | 7790            | 7790   | 7790   | 7790   | 14      |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| onMapAccounts                                   | 24389           | 146364 | 143394 | 381512 | 6       |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| onSettleData                                    | 24592           | 166723 | 146236 | 383758 | 5       |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| onSettleLiquidity                               | 24311           | 147320 | 144891 | 381679 | 5       |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| onSettleTotalLiquidity                          | 23917           | 124611 | 122320 | 314470 | 5       |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| removeHook                                      | 23866           | 29398  | 26061  | 38268  | 3       |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| transfer(address,uint256,bytes)                 | 164151          | 297607 | 275510 | 528356 | 6       |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| transfer(address,uint256,bytes,uint256,bytes)   | 528972          | 596201 | 596201 | 663430 | 2       |
|-------------------------------------------------+-----------------+--------+--------+--------+---------|
| updateReadTarget                                | 51267           | 51267  | 51267  | 51267  | 46      |
╰-------------------------------------------------+-----------------+--------+--------+--------+---------╯

╭-------------------------------------------+-----------------+-------+--------+-------+---------╮
| test/mocks/HookMock.sol:HookMock Contract |                 |       |        |       |         |
+================================================================================================+
| Deployment Cost                           | Deployment Size |       |        |       |         |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| 1768721                                   | 8024            |       |        |       |         |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
|                                           |                 |       |        |       |         |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                             | Min             | Avg   | Median | Max   | # Calls |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| afterTransferCalls                        | 11146           | 11146 | 11146  | 11146 | 2       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| beforeTransferCalls                       | 11173           | 11173 | 11173  | 11173 | 2       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| getAfterTransferCallCount                 | 2335            | 2335  | 2335   | 2335  | 9       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| getBeforeTransferCallCount                | 2375            | 2375  | 2375   | 2375  | 9       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| getGlobalAvailabilityCallCount            | 2374            | 2374  | 2374   | 2374  | 5       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| getInitiateTransferCallCount              | 2339            | 2339  | 2339   | 2339  | 5       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| getMapAccountsCallCount                   | 2358            | 2358  | 2358   | 2358  | 5       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| getSettleDataCallCount                    | 2336            | 2336  | 2336   | 2336  | 5       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| getSettleLiquidityCallCount               | 2336            | 2336  | 2336   | 2336  | 5       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| getSettleTotalLiquidityCallCount          | 2374            | 2374  | 2374   | 2374  | 5       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| globalAvailabilityCalls                   | 8770            | 8770  | 8770   | 8770  | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| initiateTransferCalls                     | 31305           | 31305 | 31305  | 31305 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| mapAccountsCalls                          | 10875           | 10875 | 10875  | 10875 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| setShouldRevertAfterTransfer              | 43618           | 43618 | 43618  | 43618 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| setShouldRevertBeforeTransfer             | 43578           | 43578 | 43578  | 43578 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| setShouldRevertOnGlobalAvailability       | 43565           | 43565 | 43565  | 43565 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| setShouldRevertOnInitiate                 | 43563           | 43563 | 43563  | 43563 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| setShouldRevertOnMapAccounts              | 43616           | 43616 | 43616  | 43616 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| setShouldRevertOnSettleData               | 43581           | 43581 | 43581  | 43581 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| setShouldRevertOnSettleLiquidity          | 43602           | 43602 | 43602  | 43602 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| setShouldRevertOnSettleTotalLiquidity     | 43600           | 43600 | 43600  | 43600 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| settleDataCalls                           | 20108           | 20108 | 20108  | 20108 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| settleLiquidityCalls                      | 10859           | 10859 | 10859  | 10859 | 1       |
|-------------------------------------------+-----------------+-------+--------+-------+---------|
| settleTotalLiquidityCalls                 | 8753            | 8753  | 8753   | 8753  | 1       |
╰-------------------------------------------+-----------------+-------+--------+-------+---------╯

╭-------------------------------------------------------------------+-----------------+-----+--------+-----+---------╮
| test/mocks/LayerZeroGatewayMock.sol:LayerZeroGatewayMock Contract |                 |     |        |     |         |
+====================================================================================================================+
| Deployment Cost                                                   | Deployment Size |     |        |     |         |
|-------------------------------------------------------------------+-----------------+-----+--------+-----+---------|
| 457935                                                            | 1907            |     |        |     |         |
|-------------------------------------------------------------------+-----------------+-----+--------+-----+---------|
|                                                                   |                 |     |        |     |         |
|-------------------------------------------------------------------+-----------------+-----+--------+-----+---------|
| Function Name                                                     | Min             | Avg | Median | Max | # Calls |
|-------------------------------------------------------------------+-----------------+-----+--------+-----+---------|
| quoteRead                                                         | 522             | 522 | 522    | 522 | 9       |
╰-------------------------------------------------------------------+-----------------+-----+--------+-----+---------╯

╭-----------------------------------------------------------------+-----------------+-------+--------+-------+---------╮
| test/mocks/LiquidityMatrixMock.sol:LiquidityMatrixMock Contract |                 |       |        |       |         |
+======================================================================================================================+
| Deployment Cost                                                 | Deployment Size |       |        |       |         |
|-----------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| 296047                                                          | 1155            |       |        |       |         |
|-----------------------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                                 |                 |       |        |       |         |
|-----------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                                                   | Min             | Avg   | Median | Max   | # Calls |
|-----------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| getLocalLiquidity                                               | 522             | 2153  | 2522   | 2522  | 76      |
|-----------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| getSettledLiquidity                                             | 2521            | 2521  | 2521   | 2521  | 27      |
|-----------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| setTotalLiquidity                                               | 44073           | 44073 | 44073  | 44073 | 46      |
|-----------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| updateLocalLiquidity                                            | 46300           | 46300 | 46300  | 46300 | 138     |
╰-----------------------------------------------------------------+-----------------+-------+--------+-------+---------╯

╭-----------------------------------------------------------+-----------------+-------+--------+-------+---------╮
| test/mocks/MockERC7540Vault.sol:MockERC7540Vault Contract |                 |       |        |       |         |
+================================================================================================================+
| Deployment Cost                                           | Deployment Size |       |        |       |         |
|-----------------------------------------------------------+-----------------+-------+--------+-------+---------|
| 1402916                                                   | 6966            |       |        |       |         |
|-----------------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                           |                 |       |        |       |         |
|-----------------------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                                             | Min             | Avg   | Median | Max   | # Calls |
|-----------------------------------------------------------+-----------------+-------+--------+-------+---------|
| asset                                                     | 257             | 257   | 257    | 257   | 120     |
|-----------------------------------------------------------+-----------------+-------+--------+-------+---------|
| claimableDepositRequest                                   | 11078           | 11078 | 11078  | 11078 | 2       |
|-----------------------------------------------------------+-----------------+-------+--------+-------+---------|
| claimableRedeemRequest                                    | 11101           | 11101 | 11101  | 11101 | 2       |
|-----------------------------------------------------------+-----------------+-------+--------+-------+---------|
| nextRequestId                                             | 2347            | 2347  | 2347   | 2347  | 2       |
|-----------------------------------------------------------+-----------------+-------+--------+-------+---------|
| pendingDepositRequest                                     | 11089           | 11089 | 11089  | 11089 | 7       |
|-----------------------------------------------------------+-----------------+-------+--------+-------+---------|
| pendingRedeemRequest                                      | 11091           | 11091 | 11091  | 11091 | 4       |
|-----------------------------------------------------------+-----------------+-------+--------+-------+---------|
| setClaimable                                              | 46018           | 47105 | 47105  | 48193 | 4       |
|-----------------------------------------------------------+-----------------+-------+--------+-------+---------|
| setPending                                                | 24022           | 25109 | 25109  | 26197 | 2       |
╰-----------------------------------------------------------+-----------------+-------+--------+-------+---------╯


Ran 13 test suites in 34.39s (48.27s CPU time): 351 tests passed, 0 failed, 0 skipped (351 total tests)
