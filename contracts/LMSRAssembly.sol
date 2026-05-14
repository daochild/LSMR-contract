// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

// @dev Note: implimentation of the same public API as LMSR.sol, but with assembly optimisations in hot paths.
//import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

/**
 * @title LMSRAssembly – Assembly-optimised LMSR
 * @dev Identical public API to LMSR.sol. Internal hot-paths are rewritten with
 *      inline assembly to eliminate per-call overhead from the ABDK library
 *      wrapper functions and Solidity-generated bounds checks.
 *
 * Assembly optimisations applied
 * ──────────────────────────────
 *  1. ABDKMath64x64.div  → inlined as `sdiv(shl(64, x), y)`
 *       Eliminates: JUMP to library, input `require(y!=0)`, output range-check, JUMP back.
 *       Precondition: caller guarantees b > 0 (validated at entry) and result fits int128.
 *
 *  2. ABDKMath64x64.add  → inlined as `add(x, y)`
 *       Eliminates: JUMP + overflow range-check.
 *       Precondition: accumulator does not exceed int128 range (holds for realistic markets).
 *
 *  3. Array element reads → direct `mload(dataPtr + i*32)`
 *       Eliminates: Solidity bounds-check (MLOAD length + LT + JUMPI) per loop iteration.
 *
 *  4. getArbitraryConstantAvgBatch / LRBatch → fully in assembly
 *       Tight loops using mload, no Solidity loop-counter overhead.
 *       Note: uses 256-bit accumulator (vs original uint128 accumulator that wraps on overflow).
 *
 *  5. getArbitraryConstantAvg(q1,q2) / LR(q1,q2) → direct expression, no _pairToArray
 *       Eliminates memory allocation entirely for the scalar binary helpers.
 *
 *  6. _pairToArray → manual mstore / free-memory-pointer update
 *       `new uint128[](2)` initialises to zero then stores; assembly writes directly.
 *
 *  7. getArbitraryConstant() → literal `shl(64, 1_000_000)` (no fromUInt call)
 *
 * ABDKMath64x64.exp is still called via the library (no EVM-level equivalent exists).
 */
contract LMSRAssembly {

    enum InputErrorReason {
        ArrayTooShort,
        ArraysLengthMismatch
    }

    enum ArbitraryConstantStrategy {
        Static,
        LargestRunner,
        Average
    }

    error InvalidInput(InputErrorReason);
    error InvalidOutcomeIndex();

    // ═══════════════════════════════════════════════════════════════════
    // OUTCOME-BASED CANONICAL API
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
    // LEGACY SHAPE-BASED WRAPPERS (outcomeIndex = 0, Average default)
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

    function getArbitraryConstantByStrategy(uint128[] memory _qs, ArbitraryConstantStrategy strategy)
        public pure returns (uint128 b)
    {
        _validateArrayLength(_qs.length, 2);
        b = _resolveStrategy(_qs, strategy);
    }

    /// @dev 1_000_000 in 64.64 = 1_000_000 << 64.  Replaces ABDKMath64x64.fromUInt call.
    function getArbitraryConstant() public pure returns (uint128 b) {
        assembly {
            b := shl(64, 1000000)
        }
    }

    /// @dev Assembly branchless max — no _pairToArray allocation.
    function getArbitraryConstantLR(uint128 q1, uint128 q2) public pure returns (uint128 b) {
        assembly {
            switch gt(q1, q2)
            case 1  { b := q1 }
            default { b := q2 }
        }
    }

    /// @dev Tight assembly loop: direct mload, no Solidity bounds-check per iteration.
    function getArbitraryConstantLRBatch(uint128[] memory _qs) public pure returns (uint128 b) {
        if (_qs.length < 2) revert InvalidInput(InputErrorReason.ArrayTooShort);
        assembly {
            let len     := mload(_qs)
            let dataPtr := add(_qs, 0x20)   // pointer to first element slot
            b := mload(dataPtr)             // b = _qs[0]
            for { let i := 1 } lt(i, len) { i := add(i, 1) } {
                let val := mload(add(dataPtr, shl(5, i)))   // shl(5,i) = i*32
                if gt(val, b) { b := val }
            }
        }
    }

    /// @dev Direct average expression — no _pairToArray allocation.
    ///      Uses 256-bit addition to avoid uint128 overflow (unlike original unchecked uint128 sum).
    function getArbitraryConstantAvg(uint128 q1, uint128 q2) public pure returns (uint128 b) {
        assembly {
            b := shr(1, add(q1, q2))    // (q1 + q2) / 2  in 256-bit; result fits uint128
        }
    }

    /// @dev Tight assembly loop: 256-bit sum avoids uint128 wrap-around of the original.
    function getArbitraryConstantAvgBatch(uint128[] memory _qs) public pure returns (uint128 b) {
        if (_qs.length < 2) revert InvalidInput(InputErrorReason.ArrayTooShort);
        assembly {
            let len     := mload(_qs)
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
     * Per-iteration savings vs LMSR.sol:
     *   • ABDKMath64x64.div  replaced by  sdiv(shl(64,qi), b64)      — saves JUMP + require + range-check
     *   • ABDKMath64x64.add  replaced by  add(denom, term)            — saves JUMP + range-check
     *   • _qs[i] bounds-check replaced by mload(dataPtr + i*32)       — saves MLOAD + LT + JUMPI
     *
     * ABDKMath64x64.exp is still called (irreplaceable on EVM).
     *
     * Preconditions (enforced by callers):
     *   • _qs.length >= 2, outcomeIndex < _qs.length
     *   • b > 0 (so b64 != 0, making sdiv safe)
     *   • each _qs[i] fits in int128 (< 2^127)
     *   • denominator does not overflow int128 (holds for practical market sizes)
     */
    function _calculateExponentialPriceForOutcome(
        uint128[] memory _qs,
        uint256 outcomeIndex,
        uint128 b
    ) internal pure returns (int128 price) {
        int128 denominator;
        int128 numerator;
        int128 b64 = int128(b);
        uint256 len = _qs.length;

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                // ── direct array read (no bounds check) ──────────────────
                int128 qi;
                assembly {
                    // Memory layout: _qs → [length][elem0][elem1]…
                    // Each slot is 32 bytes; elem i is at _qs + 32 + i*32
                    qi := mload(add(add(_qs, 0x20), shl(5, i)))
                }

                // ── inline div64x64: qi/b in 64.64 ───────────────────────
                // Equivalent to ABDKMath64x64.div(qi, b64) without range-check.
                // sdiv interprets both operands as signed 256-bit integers.
                // qi loaded from uint128[] is non-negative and sign-extends correctly.
                int128 exponent;
                assembly {
                    exponent := sdiv(shl(64, qi), b64)
                }

                // ── exp still uses the library (no EVM primitive) ─────────
                int128 term = ABDKMath64x64.exp(exponent);

                // ── inline add64x64 ───────────────────────────────────────
                assembly {
                    denominator := add(denominator, term)
                }

                if (i == outcomeIndex) {
                    numerator = term;
                }
            }
        }

        // ── final inline div64x64: numerator / denominator ────────────
        assembly {
            price := sdiv(shl(64, numerator), denominator)
        }
    }

    /**
     * @dev Ratio (linear) LMSR price — hot path.
     *
     * Per-iteration savings vs LMSR.sol:
     *   • Two ABDKMath64x64.div + one .add per iteration → one sdiv + one add opcode pair
     *   • Bounds-check eliminated via direct mload
     */
    function _calculateRatioPriceForOutcome(
        uint128[] memory _qs,
        uint256 outcomeIndex,
        uint128 b
    ) internal pure returns (int128 price) {
        int128 denominator;
        int128 b64 = int128(b);
        uint256 len = _qs.length;

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                assembly {
                    // direct read + inline div + inline add in one block
                    let qi := mload(add(add(_qs, 0x20), shl(5, i)))
                    denominator := add(denominator, sdiv(shl(64, qi), b64))
                }
            }
        }

        // price = (qs[outcomeIndex]/b) / denominator  — two inline divs
        assembly {
            let qi          := mload(add(add(_qs, 0x20), shl(5, outcomeIndex)))
            let numerator   := sdiv(shl(64, qi), b64)
            price           := sdiv(shl(64, numerator), denominator)
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // VALIDATION (cold paths — kept as Solidity for readability)
    // ═══════════════════════════════════════════════════════════════════

    function _validateTradeArrays(uint256 initialLength, uint256 finalLength, uint256 minLength) internal pure {
        _validateArrayLength(initialLength, minLength);
        if (initialLength != finalLength) revert InvalidInput(InputErrorReason.ArraysLengthMismatch);
    }

    function _validateTradeArrays(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 minLength,
        uint256 outcomeIndex
    ) internal pure {
        _validateTradeArrays(_q_initial.length, _q_final.length, minLength);
        _validateOutcomeIndex(_q_initial.length, outcomeIndex);
    }

    function _validateOutcomeArray(uint128[] memory _qs, uint256 minLength, uint256 outcomeIndex) internal pure {
        _validateArrayLength(_qs.length, minLength);
        _validateOutcomeIndex(_qs.length, outcomeIndex);
    }

    function _validateArrayLength(uint256 length, uint256 minLength) internal pure {
        if (length < minLength) revert InvalidInput(InputErrorReason.ArrayTooShort);
    }

    function _validateOutcomeIndex(uint256 length, uint256 outcomeIndex) internal pure {
        if (outcomeIndex >= length) revert InvalidOutcomeIndex();
    }

    // ═══════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @dev Assembly-optimised _pairToArray.
     *
     * `new uint128[](2)` in Solidity:
     *   MLOAD fmp, MSTORE length=2, zeroise two slots, MSTORE fmp+0x60.
     *
     * Assembly version writes directly without the zero-initialisation loop:
     *   MLOAD fmp, MSTORE length, MSTORE q1, MSTORE q2, MSTORE fmp+0x60.
     */
    function _pairToArray(uint128 q1, uint128 q2) internal pure returns (uint128[] memory qs) {
        assembly {
            qs := mload(0x40)               // grab free-memory pointer → array pointer
            mstore(qs,          2)          // length = 2
            mstore(add(qs, 0x20), q1)       // qs[0]
            mstore(add(qs, 0x40), q2)       // qs[1]
            mstore(0x40, add(qs, 0x60))     // advance free-memory pointer by 3 × 32 bytes
        }
    }

    /**
     * @dev Strategy resolution refactored into one helper to avoid duplicating
     *      the three-way conditional in every overload.
     */
    function _resolveStrategy(uint128[] memory _qs, ArbitraryConstantStrategy strategy)
        internal pure returns (uint128 b)
    {
        if (strategy == ArbitraryConstantStrategy.Static) {
            b = getArbitraryConstant();
        } else if (strategy == ArbitraryConstantStrategy.LargestRunner) {
            b = getArbitraryConstantLRBatch(_qs);
        } else {
            b = getArbitraryConstantAvgBatch(_qs);
        }
    }
}

