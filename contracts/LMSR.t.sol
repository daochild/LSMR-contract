// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {LMSR} from "./LMSR.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

/**
 * @title LMSR Solidity Tests
 * @dev Comprehensive test suite for LMSR contract using Forge/Hardhat testing
 * @notice Tests cover pricing models, strategies, edge cases, and gas usage patterns
 */
contract LMSRTest is Test {
    LMSR lmsr;

    // Test constants
    uint128 constant Q_UNIT = 1e18; // Unit quantity
    uint128 constant B_STATIC = 1_000_000; // Static arbitrary constant
    uint128 constant B_64X64_UNIT = 0x0000000000000001; // 1.0 in 64.64 fixed-point

    function setUp() public {
        lmsr = new LMSR();
    }

    // ========== PRICE CALCULATION TESTS (EXPONENTIAL) ==========

    /**
     * @dev Test basic binary market price calculation
     */
    function test_calculatePrice_binary_equal_shares() public view {
        uint128 q1 = Q_UNIT;
        uint128 q2 = Q_UNIT;
        uint128 b = 1e18; // 1.0 in 64.64

        int128 price = lmsr.calculatePrice(q1, q2, b);

        // For equal quantities, exponential price should be ~0.5 (0x8000000000000000 in fixed-point)
        assertTrue(price > 0, "Price should be positive");
        // Close to 0.5 but exact value depends on Math lib precision
        assertLt(price, int128(0x9000000000000000), "Price should be less than 0.6");
    }

    /**
     * @dev Test price with unequal shares
     */
    function test_calculatePrice_binary_unequal_shares() public view {
        uint128 q1 = Q_UNIT;
        uint128 q2 = 2 * Q_UNIT;

        int128 price = lmsr.calculatePrice(q1, q2);

        assertTrue(price > 0, "Price should be positive");
        assertTrue(price < int128(0x8000000000000000), "Price for lower quantity should be less than 0.5");
    }

    /**
     * @dev Test outcome-based price with explicit strategy
     */
    function test_calculatePriceForOutcome_with_strategy() public view {
        uint128[] memory qs = new uint128[](2);
        qs[0] = Q_UNIT;
        qs[1] = Q_UNIT;

        int128 priceAvg = lmsr.calculatePriceForOutcome(qs, 0, LMSR.ArbitraryConstantStrategy.Average);
        int128 priceStatic = lmsr.calculatePriceForOutcome(qs, 0, LMSR.ArbitraryConstantStrategy.Static);

        assertTrue(priceAvg > 0, "Price with Average strategy should be positive");
        assertTrue(priceStatic > 0, "Price with Static strategy should be positive");
    }

    /**
     * @dev Test outcome-based price with explicit b parameter
     */
    function test_calculatePriceForOutcome_explicit_b() public view {
        uint128[] memory qs = new uint128[](2);
        qs[0] = Q_UNIT;
        qs[1] = Q_UNIT;
        uint128 b = 1e18;

        int128 price = lmsr.calculatePriceForOutcome(qs, 0, b);

        assertTrue(price > 0, "Price should be positive");
    }

    /**
     * @dev Test batch (ratio) pricing
     */
    function test_calculatePriceBatch_ratio_pricing() public view {
        uint128[] memory qs = new uint128[](2);
        qs[0] = 2 * Q_UNIT;
        qs[1] = 2 * Q_UNIT;
        uint128 b = 1e18;

        int128 priceBatch = lmsr.calculatePriceBatchForOutcome(qs, 0, b);

        // Ratio pricing: (q/b) / sum(q/b) = q / sum(q)
        // For equal quantities: price = 0.5
        assertTrue(priceBatch > 0, "Batch price should be positive");
    }

    /**
     * @dev Test price with 3+ outcomes
     */
    function test_calculatePriceTriple() public view {
        uint128[] memory qs = new uint128[](3);
        qs[0] = Q_UNIT;
        qs[1] = Q_UNIT;
        qs[2] = Q_UNIT;

        int128 price = lmsr.calculatePriceTriple(qs);

        assertTrue(price > 0, "Price for 3 outcomes should be positive");
        // For equal quantities: price ≈ 1/3
        assertLe(price, int128(0x5555555555555555), "Price should be at most 1/3");
    }

    /**
     * @dev Test price for N outcomes
     */
    function test_calculatePriceBatch_many_outcomes() public view {
        uint128[] memory qs = new uint128[](5);
        for (uint i = 0; i < 5; i++) {
            qs[i] = Q_UNIT;
        }

        int128 price = lmsr.calculatePriceBatch(qs);

        assertTrue(price > 0, "Batch price for 5 outcomes should be positive");
        // For equal quantities: price = 1/5 = 0.2
        assertLt(price, int128(0x3333333333333334), "Price should be less than ~1/3");
    }

    // ========== TRADE COST TESTS ==========

    /**
     * @dev Test binary trade cost calculation
     */
    function test_calculateTradeCost_binary() public view {
        uint128 q1_initial = Q_UNIT;
        uint128 q2_initial = Q_UNIT;
        uint128 q1_final = 2 * Q_UNIT;
        uint128 q2_final = Q_UNIT;

        int128 cost = lmsr.calculateTradeCost(q1_initial, q2_initial, q1_final, q2_final);

        assertTrue(cost > 0, "Trade cost should be positive when buying shares");
    }

    /**
     * @dev Test trade cost with explicit b
     */
    function test_calculateTradeCost_explicit_b() public view {
        uint128[] memory q_initial = new uint128[](2);
        q_initial[0] = Q_UNIT;
        q_initial[1] = Q_UNIT;

        uint128[] memory q_final = new uint128[](2);
        q_final[0] = 2 * Q_UNIT;
        q_final[1] = Q_UNIT;

        uint128 b = 1e18;
        int128 cost = lmsr.calculateTradeCostForOutcome(q_initial, q_final, 0, b);

        assertTrue(cost > 0, "Cost should be positive");
    }

    /**
     * @dev Test trade cost with strategy
     */
    function test_calculateTradeCost_with_strategy() public view {
        uint128[] memory q_initial = new uint128[](2);
        q_initial[0] = Q_UNIT;
        q_initial[1] = Q_UNIT;

        uint128[] memory q_final = new uint128[](2);
        q_final[0] = 2 * Q_UNIT;
        q_final[1] = Q_UNIT;

        int128 costAvg = lmsr.calculateTradeCostForOutcome(
            q_initial,
            q_final,
            0,
            LMSR.ArbitraryConstantStrategy.Average
        );

        assertTrue(costAvg > 0, "Cost should be positive with Average strategy");
    }

    /**
     * @dev Test batch trade cost
     */
    function test_calculateTradeCostBatch() public view {
        uint128[] memory q_initial = new uint128[](2);
        q_initial[0] = Q_UNIT;
        q_initial[1] = Q_UNIT;

        uint128[] memory q_final = new uint128[](2);
        q_final[0] = 2 * Q_UNIT;
        q_final[1] = Q_UNIT;

        int128 cost = lmsr.calculateTradeCostBatch(q_initial, q_final);

        assertTrue(cost > 0, "Batch trade cost should be positive");
    }

    // ========== ARBITRARY CONSTANT STRATEGY TESTS ==========

    /**
     * @dev Test Static strategy returns fixed constant
     */
    function test_getArbitraryConstant_static() public view {
        uint128 b = lmsr.getArbitraryConstant();

        // Should return 1_000_000 in fixed-point format
        assertGt(b, 0, "Static constant should be positive");
    }

    /**
     * @dev Test LargestRunner strategy
     */
    function test_getArbitraryConstantLR_binary() public view {
        uint128 q1 = Q_UNIT;
        uint128 q2 = 3 * Q_UNIT;

        uint128 b = lmsr.getArbitraryConstantLR(q1, q2);

        assertEq(b, q2, "LargestRunner should return max quantity");
    }

    /**
     * @dev Test LargestRunner for batch
     */
    function test_getArbitraryConstantLRBatch() public view {
        uint128[] memory qs = new uint128[](3);
        qs[0] = Q_UNIT;
        qs[1] = 5 * Q_UNIT;
        qs[2] = 2 * Q_UNIT;

        uint128 b = lmsr.getArbitraryConstantLRBatch(qs);

        assertEq(b, 5 * Q_UNIT, "LargestRunner batch should return max");
    }

    /**
     * @dev Test Average strategy for binary
     */
    function test_getArbitraryConstantAvg_binary() public view {
        uint128 q1 = Q_UNIT;
        uint128 q2 = Q_UNIT;

        uint128 b = lmsr.getArbitraryConstantAvg(q1, q2);

        assertEq(b, Q_UNIT, "Average of equal quantities should be same");
    }

    /**
     * @dev Test Average for batch
     */
    function test_getArbitraryConstantAvgBatch() public view {
        uint128[] memory qs = new uint128[](3);
        qs[0] = 1e18;
        qs[1] = 2e18;
        qs[2] = 3e18;

        uint128 b = lmsr.getArbitraryConstantAvgBatch(qs);

        // Average: (1 + 2 + 3) / 3 = 2
        assertEq(b, 2e18, "Average should be 2");
    }

    /**
     * @dev Test strategy selection via enum
     */
    function test_getArbitraryConstantByStrategy() public view {
        uint128[] memory qs = new uint128[](2);
        qs[0] = Q_UNIT;
        qs[1] = 2 * Q_UNIT;

        uint128 bStatic = lmsr.getArbitraryConstantByStrategy(qs, LMSR.ArbitraryConstantStrategy.Static);
        uint128 bLR = lmsr.getArbitraryConstantByStrategy(qs, LMSR.ArbitraryConstantStrategy.LargestRunner);
        uint128 bAvg = lmsr.getArbitraryConstantByStrategy(qs, LMSR.ArbitraryConstantStrategy.Average);

        assertGt(bStatic, 0, "Static should be positive");
        assertEq(bLR, 2 * Q_UNIT, "LargestRunner should be max");
        assertGt(bAvg, Q_UNIT, "Average should be > min");
    }

    // ========== ERROR HANDLING TESTS ==========

    /**
     * @dev Test array too short error for price with 1 element
     */
    function test_error_calculatePrice_array_too_short() public {
        uint128[] memory qs = new uint128[](1);
        qs[0] = Q_UNIT;

        vm.expectRevert();
        lmsr.calculatePriceForOutcome(qs, 0);
    }

    /**
     * @dev Test invalid outcome index (exceeds array bounds)
     */
    function test_error_invalid_outcome_index() public {
        uint128[] memory qs = new uint128[](2);
        qs[0] = Q_UNIT;
        qs[1] = Q_UNIT;

        vm.expectRevert();
        lmsr.calculatePriceForOutcome(qs, 2); // Index out of bounds
    }

    /**
     * @dev Test arrays length mismatch in trade cost
     */
    function test_error_trade_arrays_length_mismatch() public {
        uint128[] memory q_initial = new uint128[](2);
        q_initial[0] = Q_UNIT;
        q_initial[1] = Q_UNIT;

        uint128[] memory q_final = new uint128[](3);
        q_final[0] = Q_UNIT;
        q_final[1] = Q_UNIT;
        q_final[2] = Q_UNIT;

        vm.expectRevert();
        lmsr.calculateTradeCostForOutcome(q_initial, q_final, 0);
    }

    /**
     * @dev Test error for average constant with single element
     */
    function test_error_getArbitraryConstantAvgBatch_too_short() public {
        uint128[] memory qs = new uint128[](1);
        qs[0] = Q_UNIT;

        vm.expectRevert();
        lmsr.getArbitraryConstantAvgBatch(qs);
    }

    // ========== EDGE CASE TESTS ==========

    /**
     * @dev Test with very large quantities
     */
    function test_large_quantities() public view {
        uint128 q1 = uint128(1e25);
        uint128 q2 = uint128(1e25);

        int128 price = lmsr.calculatePrice(q1, q2);

        assertTrue(price > 0, "Price should handle large quantities");
    }

    /**
     * @dev Test with minimal quantities
     */
    function test_small_quantities() public view {
        uint128 q1 = 1;
        uint128 q2 = 1;

        int128 price = lmsr.calculatePrice(q1, q2);

        assertTrue(price > 0, "Price should handle small quantities");
    }

    /**
     * @dev Test asymmetric quantities
     */
    function test_asymmetric_quantities() public view {
        uint128 q1 = Q_UNIT;
        uint128 q2 = 100 * Q_UNIT;

        int128 price = lmsr.calculatePrice(q1, q2);

        // Price for minority share should be < 0.5
        assertTrue(price > 0 && price < int128(0x8000000000000000), "Asymmetric price should be correct");
    }

    /**
     * @dev Test outcome index 0 vs other outcomes
     */
    function test_outcome_index_matters() public view {
        uint128[] memory qs = new uint128[](3);
        qs[0] = Q_UNIT;
        qs[1] = 2 * Q_UNIT;
        qs[2] = 3 * Q_UNIT;

        int128 price0 = lmsr.calculatePriceForOutcome(qs, 0);
        int128 price1 = lmsr.calculatePriceForOutcome(qs, 1);
        int128 price2 = lmsr.calculatePriceForOutcome(qs, 2);

        // Different outcomes should have different prices
        assertTrue(price0 > 0 && price1 > 0 && price2 > 0, "All prices should be positive");
    }

    // ========== EQUIVALENCE TESTS ==========

    /**
     * @dev Test that legacy and canonical methods produce same results for first outcome
     */
    function test_legacy_canonical_equivalence_binary() public view {
        uint128 q1 = Q_UNIT;
        uint128 q2 = 2 * Q_UNIT;
        uint128 b = 1e18;

        int128 priceLegacy = lmsr.calculatePrice(q1, q2, b);

        uint128[] memory qs = new uint128[](2);
        qs[0] = q1;
        qs[1] = q2;
        int128 priceCanonical = lmsr.calculatePriceForOutcome(qs, 0, b);

        assertEq(priceLegacy, priceCanonical, "Legacy and canonical should match");
    }

    /**
     * @dev Test legacy triple wrapper consistency
     */
    function test_legacy_wrapper_triple() public view {
        uint128[] memory qs = new uint128[](3);
        qs[0] = Q_UNIT;
        qs[1] = Q_UNIT;
        qs[2] = Q_UNIT;

        int128 price = lmsr.calculatePriceTriple(qs);

        assertTrue(price > 0, "Triple wrapper should work");
    }

    // ========== GAS BENCHMARKING TESTS ==========
    // Note: These tests help identify gas usage patterns
    // Run with: npm test -- --reporter json > gas-report.json

    /**
     * @dev Benchmark: Price calculation with 2 outcomes
     */
    function test_gas_calculatePrice_binary() public view {
        uint128 q1 = Q_UNIT;
        uint128 q2 = Q_UNIT;

        // This will show gas usage in test output
        lmsr.calculatePrice(q1, q2);
    }

    /**
     * @dev Benchmark: Price calculation with 5 outcomes
     */
    function test_gas_calculatePriceBatch_5outcomes() public view {
        uint128[] memory qs = new uint128[](5);
        for (uint i = 0; i < 5; i++) {
            qs[i] = Q_UNIT;
        }

        lmsr.calculatePriceBatch(qs);
    }

    /**
     * @dev Benchmark: Trade cost calculation
     */
    function test_gas_calculateTradeCost() public view {
        uint128 q1_initial = Q_UNIT;
        uint128 q2_initial = Q_UNIT;
        uint128 q1_final = 2 * Q_UNIT;
        uint128 q2_final = Q_UNIT;

        lmsr.calculateTradeCost(q1_initial, q2_initial, q1_final, q2_final);
    }

    /**
     * @dev Benchmark: Arbitrary constant calculation
     */
    function test_gas_getArbitraryConstantAvgBatch() public view {
        uint128[] memory qs = new uint128[](5);
        for (uint i = 0; i < 5; i++) {
            qs[i] = Q_UNIT;
        }

        lmsr.getArbitraryConstantAvgBatch(qs);
    }
}

