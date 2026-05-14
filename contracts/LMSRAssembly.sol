// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
/**
 * @title LMSRAssembly – Maximum assembly-optimised LMSR
 * @dev Identical public API to LMSR.sol.  Every path that can be expressed in
 *      Yul / inline assembly without sacrificing correctness has been converted.
 *      Only ABDKMath64x64.exp must remain a Solidity call (no EVM opcode exists).
 *
 * Optimisations over the previous assembly version
 * ─────────────────────────────────────────────────
 *  1.  ABDKMath64x64.div  → sdiv(shl(64,x),y)  no JUMP, no range-check
 *  2.  ABDKMath64x64.add  → add(x,y)            no JUMP, no overflow-check
 *  3.  Array reads        → direct mload         no Solidity bounds-check per element
 *  4.  _calculateRatioPriceForOutcome
 *        → single Yul for-loop block; zero Solidity in the function body
 *  5.  _calculateExponentialPriceForOutcome
 *        → assembly blocks consolidated; numerator branch moved into asm `if`
 *        → len / dataPtr hoisted outside loop (one-time mload)
 *  6.  getArbitraryConstantAvgBatch / LRBatch
 *        → validation + full Yul for-loop in one assembly block; no Solidity revert
 *  7.  getArbitraryConstantByStrategy
 *        → validation in assembly
 *  8.  getArbitraryConstantLR / Avg (pair)
 *        → direct expression; no _pairToArray allocation
 *  9.  getArbitraryConstant()
 *        → literal shl(64,1_000_000)
 * 10.  _pairToArray
 *        → direct mstore to free-memory pointer
 * 11.  All validation helpers (_validateArrayLength, _validateOutcomeIndex,
 *       _validateTradeArrays × 2, _validateOutcomeArray)
 *        → pure assembly revert with precomputed bytes4 error selectors
 *        → array-overload of _validateTradeArrays: three checks in ONE block (no sub-calls)
 *        → _validateOutcomeArray: two checks in ONE block (no sub-calls)
 * 12.  _resolveStrategy
 *        → assembly `if iszero` for Static (constant inlined); delegates only for LR/Avg
 */
contract LMSRAssembly {
    enum InputErrorReason {
        ArrayTooShort,
        ArraysLengthMismatch
    }
    enum ArbitraryConstantStrategy {
        Static,        // 0
        LargestRunner, // 1
        Average        // 2
    }
    error InvalidInput(InputErrorReason);
    error InvalidOutcomeIndex();
    // ── Precomputed error selectors (uint256, selector left-shifted to top 4 bytes) ───
    //
    // When mstore(ptr, _SEL_X) is called, the selector occupies ptr[0..3] and
    // zeros fill ptr[4..31].  A subsequent mstore(add(ptr, 0x04), reason) then
    // writes the ABI-encoded uint8 reason at ptr[4..35], giving valid
    // ABI-encoded custom-error data that EVM reverts can return.
    //
    // ABI layout for InvalidInput(uint8)  — 36 bytes total:
    //   ptr[0..3]  : 0xae58b8ae  (keccak256("InvalidInput(uint8)")[0:4])
    //   ptr[4..35] : uint8 padded to 32 bytes  (0 = ArrayTooShort, 1 = ArraysLengthMismatch)
    //
    // ABI layout for InvalidOutcomeIndex()  — 4 bytes total:
    //   ptr[0..3]  : 0xbdc95715  (keccak256("InvalidOutcomeIndex()")[0:4])
    //
    // Only uint256 literals are allowed in Yul assembly blocks (Solidity 0.8 constraint).
    uint256 internal constant _SEL_INVALID_INPUT =
        0xae58b8ae00000000000000000000000000000000000000000000000000000000;
    uint256 internal constant _SEL_INVALID_OUTCOME_IDX =
        0xbdc9571500000000000000000000000000000000000000000000000000000000;
    // ═══════════════════════════════════════════════════════════════════
    // OUTCOME-BASED CANONICAL API  (signatures identical to LMSR.sol)
    // ═══════════════════════════════════════════════════════════════════
    function calculatePriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex, uint128 b)
        public pure returns (int128 price)
    {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        price = _calculateExponentialPriceForOutcome(_qs, outcomeIndex, b);
    }
    function calculatePriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex)
        public pure returns (int128 price)
    {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        price = _calculateExponentialPriceForOutcome(_qs, outcomeIndex, getArbitraryConstantAvgBatch(_qs));
    }
    function calculatePriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex, ArbitraryConstantStrategy strategy)
        public pure returns (int128 price)
    {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        price = _calculateExponentialPriceForOutcome(_qs, outcomeIndex, _resolveStrategy(_qs, strategy));
    }
    function calculatePriceBatchForOutcome(uint128[] memory _qs, uint256 outcomeIndex, uint128 b)
        public pure returns (int128 price)
    {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        price = _calculateRatioPriceForOutcome(_qs, outcomeIndex, b);
    }
    function calculatePriceBatchForOutcome(uint128[] memory _qs, uint256 outcomeIndex)
        public pure returns (int128 price)
    {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        price = _calculateRatioPriceForOutcome(_qs, outcomeIndex, getArbitraryConstantAvgBatch(_qs));
    }
    function calculatePriceBatchForOutcome(uint128[] memory _qs, uint256 outcomeIndex, ArbitraryConstantStrategy strategy)
        public pure returns (int128 price)
    {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        price = _calculateRatioPriceForOutcome(_qs, outcomeIndex, _resolveStrategy(_qs, strategy));
    }
    function calculateTradeCostForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex,
        uint128 b
    ) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);
        cost = _calculateExponentialPriceForOutcome(_q_final,   outcomeIndex, b)
             - _calculateExponentialPriceForOutcome(_q_initial, outcomeIndex, b);
    }
    function calculateTradeCostForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex
    ) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);
        cost = _calculateExponentialPriceForOutcome(_q_final,   outcomeIndex, getArbitraryConstantAvgBatch(_q_final))
             - _calculateExponentialPriceForOutcome(_q_initial, outcomeIndex, getArbitraryConstantAvgBatch(_q_initial));
    }
    function calculateTradeCostForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex,
        ArbitraryConstantStrategy strategy
    ) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);
        cost = _calculateExponentialPriceForOutcome(_q_final,   outcomeIndex, _resolveStrategy(_q_final,   strategy))
             - _calculateExponentialPriceForOutcome(_q_initial, outcomeIndex, _resolveStrategy(_q_initial, strategy));
    }
    function calculateTradeCostBatchForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex,
        uint128 b
    ) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);
        cost = _calculateRatioPriceForOutcome(_q_final,   outcomeIndex, b)
             - _calculateRatioPriceForOutcome(_q_initial, outcomeIndex, b);
    }
    function calculateTradeCostBatchForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex
    ) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);
        cost = _calculateRatioPriceForOutcome(_q_final,   outcomeIndex, getArbitraryConstantAvgBatch(_q_final))
             - _calculateRatioPriceForOutcome(_q_initial, outcomeIndex, getArbitraryConstantAvgBatch(_q_initial));
    }
    function calculateTradeCostBatchForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex,
        ArbitraryConstantStrategy strategy
    ) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);
        cost = _calculateRatioPriceForOutcome(_q_final,   outcomeIndex, _resolveStrategy(_q_final,   strategy))
             - _calculateRatioPriceForOutcome(_q_initial, outcomeIndex, _resolveStrategy(_q_initial, strategy));
    }
    // ═══════════════════════════════════════════════════════════════════
    // LEGACY SHAPE-BASED WRAPPERS  (outcomeIndex = 0, Average default)
    // ═══════════════════════════════════════════════════════════════════
    function calculatePrice(uint128 q1, uint128 q2, uint128 b) public pure returns (int128 price) {
        price = calculatePriceForOutcome(_pairToArray(q1, q2), 0, b);
    }
    function calculatePrice(uint128 q1, uint128 q2) public pure returns (int128 price) {
        price = calculatePriceForOutcome(_pairToArray(q1, q2), 0, ArbitraryConstantStrategy.Average);
    }
    function calculatePriceN(uint128[] memory _qs) public pure returns (int128 price) {
        price = calculatePriceForOutcome(_qs, 0, ArbitraryConstantStrategy.Average);
    }
    function calculatePriceBatch(uint128[] memory _qs) public pure returns (int128 price) {
        price = calculatePriceBatchForOutcome(_qs, 0, ArbitraryConstantStrategy.Average);
    }
    function calculateTradeCost(
        uint128 q1_initial, uint128 q2_initial,
        uint128 q1_final,   uint128 q2_final,
        uint128 b
    ) public pure returns (int128 cost) {
        cost = calculateTradeCostForOutcome(
            _pairToArray(q1_initial, q2_initial),
            _pairToArray(q1_final,   q2_final),
            0, b
        );
    }
    function calculateTradeCost(
        uint128 q1_initial, uint128 q2_initial,
        uint128 q1_final,   uint128 q2_final
    ) public pure returns (int128 cost) {
        cost = calculateTradeCostForOutcome(
            _pairToArray(q1_initial, q2_initial),
            _pairToArray(q1_final,   q2_final),
            0, ArbitraryConstantStrategy.Average
        );
    }
    function calculateTradeCostN(uint128[] memory _q_initial, uint128[] memory _q_final)
        public pure returns (int128 cost)
    {
        cost = calculateTradeCostForOutcome(_q_initial, _q_final, 0, ArbitraryConstantStrategy.Average);
    }
    function calculateTradeCostBatch(uint128[] memory _q_initial, uint128[] memory _q_final)
        public pure returns (int128 cost)
    {
        cost = calculateTradeCostBatchForOutcome(_q_initial, _q_final, 0, ArbitraryConstantStrategy.Average);
    }
    // ═══════════════════════════════════════════════════════════════════
    // ARBITRARY CONSTANT SELECTION
    // ═══════════════════════════════════════════════════════════════════
    /// @dev Assembly length validation; delegates to _resolveStrategy.
    function getArbitraryConstantByStrategy(uint128[] memory _qs, ArbitraryConstantStrategy strategy)
        public pure returns (uint128 b)
    {
        assembly {
            if lt(mload(_qs), 2) {
                let ptr := mload(0x40)
                mstore(ptr, _SEL_INVALID_INPUT)
                mstore(add(ptr, 0x04), 0)       // ArrayTooShort = 0
                revert(ptr, 0x24)
            }
        }
        b = _resolveStrategy(_qs, strategy);
    }
    /// @dev 1_000_000 << 64 in assembly — no library call.
    function getArbitraryConstant() public pure returns (uint128 b) {
        assembly { b := shl(64, 1000000) }
    }
    /// @dev Assembly switch: max without _pairToArray allocation.
    function getArbitraryConstantLR(uint128 q1, uint128 q2) public pure returns (uint128 b) {
        assembly {
            switch gt(q1, q2)
            case 1  { b := q1 }
            default { b := q2 }
        }
    }
    /// @dev Validation + full Yul for-loop in one assembly block.  No Solidity in body.
    function getArbitraryConstantLRBatch(uint128[] memory _qs) public pure returns (uint128 b) {
        assembly {
            let len := mload(_qs)
            if lt(len, 2) {
                let ptr := mload(0x40)
                mstore(ptr, _SEL_INVALID_INPUT)
                mstore(add(ptr, 0x04), 0)           // ArrayTooShort
                revert(ptr, 0x24)
            }
            let dataPtr := add(_qs, 0x20)
            b := mload(dataPtr)                     // initialise to _qs[0]
            for { let i := 1 } lt(i, len) { i := add(i, 1) } {
                let val := mload(add(dataPtr, shl(5, i)))   // shl(5,i) == i*32
                if gt(val, b) { b := val }
            }
        }
    }
    /// @dev Direct (q1+q2)>>1 in assembly — no _pairToArray.
    function getArbitraryConstantAvg(uint128 q1, uint128 q2) public pure returns (uint128 b) {
        assembly { b := shr(1, add(q1, q2)) }
    }
    /// @dev Validation + full Yul for-loop in one assembly block.
    ///      Uses 256-bit accumulator (fixes uint128 wrap-around in original Solidity).
    function getArbitraryConstantAvgBatch(uint128[] memory _qs) public pure returns (uint128 b) {
        assembly {
            let len := mload(_qs)
            if lt(len, 2) {
                let ptr := mload(0x40)
                mstore(ptr, _SEL_INVALID_INPUT)
                mstore(add(ptr, 0x04), 0)           // ArrayTooShort
                revert(ptr, 0x24)
            }
            let dataPtr := add(_qs, 0x20)
            let sum     := 0
            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                sum := add(sum, mload(add(dataPtr, shl(5, i))))
            }
            b := div(sum, len)
        }
    }
    // ═══════════════════════════════════════════════════════════════════
    // INTERNAL OPTIMISED IMPLEMENTATIONS
    // ═══════════════════════════════════════════════════════════════════
    /**
     * @dev Exponential LMSR price — hot path.
     *
     * Cannot be a single assembly block: ABDKMath64x64.exp must be called as a
     * Solidity internal function.  However every operation AROUND that call:
     *   • len + dataPtr — read once before the loop (single mload each)
     *   • qi read + exponent computation — one assembly block per iteration
     *   • denominator accumulation + numerator capture — one assembly block (asm `if`)
     *   • final price division — one assembly block
     *
     * Per-iteration savings vs LMSR.sol:
     *   ABDKMath64x64.div  ×1 → sdiv opcode    saves JUMP + require + range-check
     *   ABDKMath64x64.add  ×1 → add opcode      saves JUMP + overflow-check
     *   _qs[i] bounds-check   → mload            saves MLOAD + LT + JUMPI
     *   `if (i==idx)` Solidity → asm `if eq`    saves Solidity-emitted JUMPI overhead
     */
    function _calculateExponentialPriceForOutcome(
        uint128[] memory _qs,
        uint256 outcomeIndex,
        uint128 b
    ) internal pure returns (int128 price) {
        int128 denominator;
        int128 numerator;
        int128 b64 = int128(b);
        uint256 len;
        uint256 dataPtr;
        // Hoist len + dataPtr: avoids one mload(_qs) + one add per iteration.
        assembly {
            len     := mload(_qs)
            dataPtr := add(_qs, 0x20)
        }
        unchecked {
            for (uint256 i = 0; i < len; i++) {
                // ── (a) direct read + inline div64x64: qi/b in 64.64 ──────
                int128 exponent;
                assembly {
                    let qi   := mload(add(dataPtr, shl(5, i)))
                    exponent := sdiv(shl(64, qi), b64)
                }
                // ── (b) exp — library call, irreplaceable ──────────────────
                int128 term = ABDKMath64x64.exp(exponent);
                // ── (c) inline add64x64 + asm conditional ─────────────────
                assembly {
                    denominator := add(denominator, term)
                    if eq(i, outcomeIndex) { numerator := term }
                }
            }
        }
        // ── (d) final inline div64x64: numerator / denominator ─────────────
        assembly {
            price := sdiv(shl(64, numerator), denominator)
        }
    }
    /**
     * @dev Ratio (linear) LMSR price — single Yul assembly block.
     *
     * No Solidity function calls required, so the ENTIRE body is one assembly
     * block with a Yul for-loop.  Eliminates:
     *   • Solidity for-loop preamble / postamble opcodes
     *   • ABDKMath64x64.div JUMP + range-check × N
     *   • ABDKMath64x64.add JUMP + overflow-check × N
     *   • Solidity memory-array bounds-check × N
     *   • Intermediate Solidity variables (b64, len, denominator live in Yul locals)
     */
    function _calculateRatioPriceForOutcome(
        uint128[] memory _qs,
        uint256 outcomeIndex,
        uint128 b
    ) internal pure returns (int128 price) {
        assembly {
            let len         := mload(_qs)
            let dataPtr     := add(_qs, 0x20)
            let denominator := 0
            // Accumulate denominator = sum(qi / b) for all outcomes.
            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                let qi := mload(add(dataPtr, shl(5, i)))
                // Inline div64x64: (qi << 64) / b  (b is uint128 < 2^127, safe for sdiv)
                denominator := add(denominator, sdiv(shl(64, qi), b))
            }
            // price = (qs[outcomeIndex] / b) / denominator  (two inline divs)
            let qi_out    := mload(add(dataPtr, shl(5, outcomeIndex)))
            let numerator := sdiv(shl(64, qi_out), b)
            price         := sdiv(shl(64, numerator), denominator)
        }
    }
    // ═══════════════════════════════════════════════════════════════════
    // VALIDATION — pure assembly, precomputed error selectors
    // ═══════════════════════════════════════════════════════════════════
    function _validateArrayLength(uint256 length, uint256 minLength) internal pure {
        assembly {
            if lt(length, minLength) {
                let ptr := mload(0x40)
                mstore(ptr, _SEL_INVALID_INPUT)
                mstore(add(ptr, 0x04), 0)       // ArrayTooShort = 0
                revert(ptr, 0x24)
            }
        }
    }
    function _validateOutcomeIndex(uint256 length, uint256 outcomeIndex) internal pure {
        assembly {
            // revert if outcomeIndex >= length
            if iszero(lt(outcomeIndex, length)) {
                let ptr := mload(0x40)
                mstore(ptr, _SEL_INVALID_OUTCOME_IDX)
                revert(ptr, 0x04)
            }
        }
    }
    /// @dev Checks minLength then equality — two checks in one assembly block.
    function _validateTradeArrays(uint256 initialLength, uint256 finalLength, uint256 minLength) internal pure {
        assembly {
            let ptr := mload(0x40)
            if lt(initialLength, minLength) {
                mstore(ptr, _SEL_INVALID_INPUT)
                mstore(add(ptr, 0x04), 0)       // ArrayTooShort
                revert(ptr, 0x24)
            }
            if iszero(eq(initialLength, finalLength)) {
                mstore(ptr, _SEL_INVALID_INPUT)
                mstore(add(ptr, 0x04), 1)       // ArraysLengthMismatch
                revert(ptr, 0x24)
            }
        }
    }
    /// @dev All THREE checks (minLen, length equality, outcomeIndex) in ONE assembly block.
    ///      Reads array lengths via mload — eliminates two JUMP sub-calls to helpers.
    function _validateTradeArrays(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 minLength,
        uint256 outcomeIndex
    ) internal pure {
        assembly {
            let initialLen := mload(_q_initial)
            let finalLen   := mload(_q_final)
            let ptr        := mload(0x40)
            if lt(initialLen, minLength) {
                mstore(ptr, _SEL_INVALID_INPUT)
                mstore(add(ptr, 0x04), 0)       // ArrayTooShort
                revert(ptr, 0x24)
            }
            if iszero(eq(initialLen, finalLen)) {
                mstore(ptr, _SEL_INVALID_INPUT)
                mstore(add(ptr, 0x04), 1)       // ArraysLengthMismatch
                revert(ptr, 0x24)
            }
            if iszero(lt(outcomeIndex, initialLen)) {
                mstore(ptr, _SEL_INVALID_OUTCOME_IDX)
                revert(ptr, 0x04)
            }
        }
    }
    /// @dev BOTH checks (minLen, outcomeIndex) in ONE assembly block — no sub-calls.
    function _validateOutcomeArray(uint128[] memory _qs, uint256 minLength, uint256 outcomeIndex) internal pure {
        assembly {
            let len := mload(_qs)
            let ptr := mload(0x40)
            if lt(len, minLength) {
                mstore(ptr, _SEL_INVALID_INPUT)
                mstore(add(ptr, 0x04), 0)       // ArrayTooShort
                revert(ptr, 0x24)
            }
            if iszero(lt(outcomeIndex, len)) {
                mstore(ptr, _SEL_INVALID_OUTCOME_IDX)
                revert(ptr, 0x04)
            }
        }
    }
    // ═══════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════
    /**
     * @dev Assembly free-memory-pointer allocation.
     *      Saves the zero-initialisation loop that `new uint128[](2)` emits.
     */
    function _pairToArray(uint128 q1, uint128 q2) internal pure returns (uint128[] memory qs) {
        assembly {
            qs := mload(0x40)
            mstore(qs,          2)              // length = 2
            mstore(add(qs, 0x20), q1)           // qs[0]
            mstore(add(qs, 0x40), q2)           // qs[1]
            mstore(0x40, add(qs, 0x60))         // advance free-memory pointer
        }
    }
    /**
     * @dev Strategy resolver.
     *      Static (0): fully inlined in assembly — no function call at all.
     *      LargestRunner / Average: delegate to already-assembly-optimised helpers.
     */
    function _resolveStrategy(uint128[] memory _qs, ArbitraryConstantStrategy strategy)
        internal pure returns (uint128 b)
    {
        // Static branch fully in assembly: literal shift, zero additional calls.
        assembly {
            if iszero(strategy) {
                b := shl(64, 1000000)
            }
        }
        // Remaining branches must call Solidity functions (already pure assembly internally).
        if (strategy == ArbitraryConstantStrategy.LargestRunner) {
            b = getArbitraryConstantLRBatch(_qs);
        } else if (strategy == ArbitraryConstantStrategy.Average) {
            b = getArbitraryConstantAvgBatch(_qs);
        }
    }
}
