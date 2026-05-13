// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

/**
 * @title ILMSR - Logarithmic Market Scoring Rule Interface
 * @dev Pure mathematical interface for LMSR pricing calculations in prediction markets
 * @notice All functions are pure and state-free; no storage or side effects
 *
 * LMSR (Logarithmic Market Scoring Rule) is a principled mechanism for calculating
 * fair prices for contingent claims (outcomes) based on outstanding shares quantities.
 * This interface defines two pricing models:
 * - Exponential: price = e^(q_i/b) / sum(e^(q_j/b)) [canonical LMSR formula]
 * - Ratio: price = (q_i/b) / sum(q_j/b) [linear approximation for batch operations]
 */
interface ILMSR {
    /**
     * @dev Enumeration for selecting how the arbitrary constant `b` is computed
     */
    enum ArbitraryConstantStrategy {
        Static,        // Fixed constant b = 1,000,000
        LargestRunner, // b = max(q_i)
        Average        // b = mean(q_i)
    }

    /**
     * @dev Input validation error reasons
     */
    enum InputErrorReason {
        ArrayTooShort,        // Array has fewer than 2 elements
        ArraysLengthMismatch  // Two arrays have different lengths
    }

    /**
     * @dev Raised when input array is too short or arrays lengths don't match
     */
    error InvalidInput(InputErrorReason);

    /**
     * @dev Raised when outcome index exceeds array bounds
     */
    error InvalidOutcomeIndex();

    // ========== OUTCOME-BASED CANONICAL API ==========
    // Recommended: Use these methods explicitly. Outcome index makes intent clear.

    /**
     * @notice Calculate exponential LMSR price for a specific outcome (with explicit b)
     * @param _qs Array of outstanding share quantities for each outcome
     * @param outcomeIndex Index of the outcome to price (must be < _qs.length)
     * @param b Arbitrary constant (scaling factor in fixed-point 64.64 format)
     * @return price Share price as fixed-point 64.64 int128 value
     * @dev Formula: e^(q_i/b) / sum(e^(q_j/b))
     */
    function calculatePriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex, uint128 b)
        external
        pure
        returns (int128 price);

    /**
     * @notice Calculate exponential LMSR price (uses Average strategy for b)
     * @param _qs Array of outstanding share quantities
     * @param outcomeIndex Index of the outcome to price
     * @return price Share price as fixed-point 64.64 int128
     */
    function calculatePriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex)
        external
        pure
        returns (int128 price);

    /**
     * @notice Calculate exponential LMSR price (with strategy selection)
     * @param _qs Array of outstanding share quantities
     * @param outcomeIndex Index of the outcome to price
     * @param strategy How to compute b: Static, LargestRunner, or Average
     * @return price Share price as fixed-point 64.64 int128
     */
    function calculatePriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex, ArbitraryConstantStrategy strategy)
        external
        pure
        returns (int128 price);

    /**
     * @notice Calculate ratio LMSR price for batch operations (with explicit b)
     * @param _qs Array of outstanding share quantities
     * @param outcomeIndex Index of the outcome to price
     * @param b Arbitrary constant (fixed-point 64.64)
     * @return price Share price as fixed-point 64.64 int128
     * @dev Formula: (q_i/b) / sum(q_j/b) [linear pricing, fast for batch use]
     */
    function calculatePriceBatchForOutcome(uint128[] memory _qs, uint256 outcomeIndex, uint128 b)
        external
        pure
        returns (int128 price);

    /**
     * @notice Calculate ratio LMSR price (uses Average strategy)
     * @param _qs Array of outstanding share quantities
     * @param outcomeIndex Index of the outcome to price
     * @return price Share price as fixed-point 64.64 int128
     */
    function calculatePriceBatchForOutcome(uint128[] memory _qs, uint256 outcomeIndex)
        external
        pure
        returns (int128 price);

    /**
     * @notice Calculate ratio LMSR price (with strategy selection)
     * @param _qs Array of outstanding share quantities
     * @param outcomeIndex Index of the outcome to price
     * @param strategy How to compute b
     * @return price Share price as fixed-point 64.64 int128
     */
    function calculatePriceBatchForOutcome(uint128[] memory _qs, uint256 outcomeIndex, ArbitraryConstantStrategy strategy)
        external
        pure
        returns (int128 price);

    /**
     * @notice Calculate trade cost (price delta) from initial to final state (with explicit b)
     * @param _q_initial Array of initial share quantities
     * @param _q_final Array of final share quantities
     * @param outcomeIndex Index of the outcome being priced
     * @param b Arbitrary constant (fixed-point 64.64)
     * @return cost Price difference using exponential formula
     * @dev Computes: price(_q_final) - price(_q_initial)
     */
    function calculateTradeCostForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex,
        uint128 b
    )
        external
        pure
        returns (int128 cost);

    /**
     * @notice Calculate trade cost (uses Average strategy)
     * @param _q_initial Array of initial share quantities
     * @param _q_final Array of final share quantities
     * @param outcomeIndex Index of the outcome
     * @return cost Price delta using exponential formula
     */
    function calculateTradeCostForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex
    )
        external
        pure
        returns (int128 cost);

    /**
     * @notice Calculate trade cost (with strategy selection)
     * @param _q_initial Array of initial share quantities
     * @param _q_final Array of final share quantities
     * @param outcomeIndex Index of the outcome
     * @param strategy How to compute b for each state
     * @return cost Price delta
     * @dev With dynamic strategies, b is recomputed at initial and final states
     */
    function calculateTradeCostForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex,
        ArbitraryConstantStrategy strategy
    )
        external
        pure
        returns (int128 cost);

    /**
     * @notice Calculate trade cost using batch (ratio) pricing (with explicit b)
     * @param _q_initial Array of initial share quantities
     * @param _q_final Array of final share quantities
     * @param outcomeIndex Index of the outcome
     * @param b Arbitrary constant (fixed-point 64.64)
     * @return cost Price delta using ratio formula
     */
    function calculateTradeCostBatchForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex,
        uint128 b
    )
        external
        pure
        returns (int128 cost);

    /**
     * @notice Calculate trade cost using batch pricing (uses Average strategy)
     * @param _q_initial Array of initial share quantities
     * @param _q_final Array of final share quantities
     * @param outcomeIndex Index of the outcome
     * @return cost Price delta using ratio formula
     */
    function calculateTradeCostBatchForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex
    )
        external
        pure
        returns (int128 cost);

    /**
     * @notice Calculate trade cost using batch pricing (with strategy selection)
     * @param _q_initial Array of initial share quantities
     * @param _q_final Array of final share quantities
     * @param outcomeIndex Index of the outcome
     * @param strategy How to compute b
     * @return cost Price delta using ratio formula
     */
    function calculateTradeCostBatchForOutcome(
        uint128[] memory _q_initial,
        uint128[] memory _q_final,
        uint256 outcomeIndex,
        ArbitraryConstantStrategy strategy
    )
        external
        pure
        returns (int128 cost);

    // ========== LEGACY SHAPE-BASED WRAPPERS ==========
    // For backwards compatibility. These default to outcomeIndex=0 and Average strategy.

    /**
     * @notice Legacy: Calculate price for binary market (outcome index hardcoded to 0)
     * @param q1 Outstanding shares for first outcome (priced outcome)
     * @param q2 Outstanding shares for second outcome
     * @param b Arbitrary constant
     * @return price Share price as fixed-point 64.64 int128
     */
    function calculatePrice(uint128 q1, uint128 q2, uint128 b) external pure returns (int128 price);

    /**
     * @notice Legacy: Calculate price for binary market (uses Average strategy)
     * @param q1 Outstanding shares for priced outcome
     * @param q2 Outstanding shares for other outcome
     * @return price Share price
     */
    function calculatePrice(uint128 q1, uint128 q2) external pure returns (int128 price);

    /**
     * @notice Calculate exponential LMSR price for any N≥2 outcomes (outcome 0, Average strategy)
     * @dev General replacement for the shape-specific calculatePrice wrappers.
     *      Use calculatePriceForOutcome when you need a specific outcome index or strategy.
     * @param _qs Array of outstanding share quantities (length ≥ 2)
     * @return price Share price for outcome 0 as fixed-point 64.64 int128
     */
    function calculatePriceN(uint128[] memory _qs) external pure returns (int128 price);

    /**
     * @notice Legacy: Calculate price for any N-outcome market (outcome index = 0)
     * @param _qs Array of share quantities for all outcomes
     * @return price Share price for first outcome using ratio (batch) formula
     */
    function calculatePriceBatch(uint128[] memory _qs) external pure returns (int128 price);

    /**
     * @notice Legacy: Calculate trade cost for binary market
     * @param q1_initial Initial shares for first outcome
     * @param q2_initial Initial shares for second outcome
     * @param q1_final Final shares for first outcome
     * @param q2_final Final shares for second outcome
     * @param b Arbitrary constant
     * @return cost Cost delta for first outcome
     */
    function calculateTradeCost(
        uint128 q1_initial,
        uint128 q2_initial,
        uint128 q1_final,
        uint128 q2_final,
        uint128 b
    )
        external
        pure
        returns (int128 cost);

    /**
     * @notice Legacy: Calculate trade cost for binary market (uses Average strategy)
     * @param q1_initial Initial shares for first outcome
     * @param q2_initial Initial shares for second outcome
     * @param q1_final Final shares for first outcome
     * @param q2_final Final shares for second outcome
     * @return cost Cost delta
     */
    function calculateTradeCost(
        uint128 q1_initial,
        uint128 q2_initial,
        uint128 q1_final,
        uint128 q2_final
    )
        external
        pure
        returns (int128 cost);

    /**
     * @notice Calculate trade cost for any N≥2 outcomes (outcome 0, Average strategy)
     * @dev General replacement for calculateTradeCost wrappers.
     *      Use calculateTradeCostForOutcome when you need a specific outcome index or strategy.
     * @param _q_initial Array of initial share quantities (length ≥ 2)
     * @param _q_final   Array of final share quantities (same length as _q_initial)
     * @return cost Price delta (final − initial) for outcome 0 as fixed-point 64.64 int128
     */
    function calculateTradeCostN(uint128[] memory _q_initial, uint128[] memory _q_final)
        external
        pure
        returns (int128 cost);

    /**
     * @notice Legacy: Calculate trade cost for any N-outcome market (outcome index = 0)
     * @param _q_initial Array of initial quantities
     * @param _q_final Array of final quantities
     * @return cost Cost delta for first outcome using ratio (batch) formula
     */
    function calculateTradeCostBatch(uint128[] memory _q_initial, uint128[] memory _q_final)
        external
        pure
        returns (int128 cost);

    // ========== ARBITRARY CONSTANT SELECTION ==========

    /**
     * @notice Get the arbitrary constant b based on a strategy
     * @param _qs Array of share quantities
     * @param strategy Strategy to use (Static, LargestRunner, or Average)
     * @return b Computed arbitrary constant in fixed-point 64.64 format
     */
    function getArbitraryConstantByStrategy(uint128[] memory _qs, ArbitraryConstantStrategy strategy)
        external
        pure
        returns (uint128 b);

    /**
     * @notice Get static arbitrary constant
     * @return b Fixed value 1,000,000 in fixed-point 64.64 format
     */
    function getArbitraryConstant() external pure returns (uint128 b);

    /**
     * @notice Get arbitrary constant as largest runner (max share quantity) for binary market
     * @param q1 First outcome share quantity
     * @param q2 Second outcome share quantity
     * @return b max(q1, q2)
     */
    function getArbitraryConstantLR(uint128 q1, uint128 q2) external pure returns (uint128 b);

    /**
     * @notice Get arbitrary constant as largest runner (max share quantity)
     * @param _qs Array of share quantities
     * @return b Maximum value in array
     */
    function getArbitraryConstantLRBatch(uint128[] memory _qs) external pure returns (uint128 b);

    /**
     * @notice Get arbitrary constant as average of share quantities for binary market
     * @param q1 First outcome share quantity
     * @param q2 Second outcome share quantity
     * @return b (q1 + q2) / 2
     */
    function getArbitraryConstantAvg(uint128 q1, uint128 q2) external pure returns (uint128 b);

    /**
     * @notice Get arbitrary constant as average of share quantities
     * @param _qs Array of share quantities
     * @return b sum(_qs) / _qs.length
     */
    function getArbitraryConstantAvgBatch(uint128[] memory _qs) external pure returns (uint128 b);
}

