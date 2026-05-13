// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

/**
 * @title LMSR - Logarithmic Market Scoring Rule
 * @dev LMSR contract to calculate the price of a share based on the number of outstanding shares
 * @notice price calculated only for q1 or _qs[0]
 *
 * @author Pavlo Bolhar - pavlo.bolhar@proton.me
 */
contract LMSR {
    using ABDKMath64x64 for int128;

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

    function calculatePriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex, uint128 b) public pure returns (int128 price) {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        price = _calculateExponentialPriceForOutcome(_qs, outcomeIndex, b);
    }

    function calculatePriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex) public pure returns (int128 price) {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        price = _calculateExponentialPriceForOutcome(_qs, outcomeIndex, getArbitraryConstantAvgBatch(_qs));
    }

    function calculatePriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex, ArbitraryConstantStrategy strategy) public pure returns (int128 price) {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        uint128 b = strategy == ArbitraryConstantStrategy.Static
            ? getArbitraryConstant()
            : (strategy == ArbitraryConstantStrategy.LargestRunner
                ? getArbitraryConstantLRBatch(_qs)
                : getArbitraryConstantAvgBatch(_qs));
        price = _calculateExponentialPriceForOutcome(_qs, outcomeIndex, b);
    }

    function calculatePriceBatchForOutcome(uint128[] memory _qs, uint256 outcomeIndex, uint128 b) public pure returns (int128 price) {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        price = _calculateRatioPriceForOutcome(_qs, outcomeIndex, b);
    }

    function calculatePriceBatchForOutcome(uint128[] memory _qs, uint256 outcomeIndex) public pure returns (int128 price) {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        price = _calculateRatioPriceForOutcome(_qs, outcomeIndex, getArbitraryConstantAvgBatch(_qs));
    }

    function calculatePriceBatchForOutcome(uint128[] memory _qs, uint256 outcomeIndex, ArbitraryConstantStrategy strategy) public pure returns (int128 price) {
        _validateOutcomeArray(_qs, 2, outcomeIndex);
        uint128 b = strategy == ArbitraryConstantStrategy.Static
            ? getArbitraryConstant()
            : (strategy == ArbitraryConstantStrategy.LargestRunner
                ? getArbitraryConstantLRBatch(_qs)
                : getArbitraryConstantAvgBatch(_qs));
        price = _calculateRatioPriceForOutcome(_qs, outcomeIndex, b);
    }

    // Equation: price = e^(q1/b) / (e^(q1/b) + e^(q2/b))
    //
    // In this formula, b is an arbitrary constant, q1 is the number of outstanding
    // shares in the stock for which you're calculating the price,
    // and q2 is the number of outstanding shares in the other stock. e - logarithm
    // Function to calculate the price based on q1, q2, and b
    function calculatePrice(uint128 q1, uint128 q2, uint128 b) public pure returns (int128 price) {
        price = calculatePriceForOutcome(_pairToArray(q1, q2), 0, b);
    }

    function calculatePrice(uint128 q1, uint128 q2) public pure returns (int128 price) {
        price = calculatePriceForOutcome(_pairToArray(q1, q2), 0, ArbitraryConstantStrategy.Average);
    }


    /**
     * @notice Calculate LMSR exponential price for any N≥2 outcomes (outcome 0, Average strategy)
     * @dev Generalisation of calculatePrice/calculatePriceTriple for arbitrary market sizes.
     *      Use calculatePriceForOutcome when you need a specific outcome index or strategy.
     * @param _qs Array of outstanding share quantities (length ≥ 2)
     * @return price Share price for outcome 0 as fixed-point 64.64 int128
     */
    function calculatePriceN(uint128[] memory _qs) public pure returns (int128 price) {
        price = calculatePriceForOutcome(_qs, 0, ArbitraryConstantStrategy.Average);
    }

    // price of q1
    function calculatePriceBatch(uint128[] memory _qs) public pure returns (int128 price) {
        price = calculatePriceBatchForOutcome(_qs, 0, ArbitraryConstantStrategy.Average);
    }

    function calculateTradeCostForOutcome(uint128[] memory _q_initial, uint128[] memory _q_final, uint256 outcomeIndex, uint128 b) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);

        int128 costInitial = _calculateExponentialPriceForOutcome(_q_initial, outcomeIndex, b);
        int128 costFinal = _calculateExponentialPriceForOutcome(_q_final, outcomeIndex, b);
        cost = costFinal - costInitial;
    }

    function calculateTradeCostForOutcome(uint128[] memory _q_initial, uint128[] memory _q_final, uint256 outcomeIndex) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);
        int128 costInitial = _calculateExponentialPriceForOutcome(_q_initial, outcomeIndex, getArbitraryConstantAvgBatch(_q_initial));
        int128 costFinal = _calculateExponentialPriceForOutcome(_q_final, outcomeIndex, getArbitraryConstantAvgBatch(_q_final));
        cost = costFinal - costInitial;
    }

    function calculateTradeCostForOutcome(uint128[] memory _q_initial, uint128[] memory _q_final, uint256 outcomeIndex, ArbitraryConstantStrategy strategy) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);

        uint128 initialB = strategy == ArbitraryConstantStrategy.Static
            ? getArbitraryConstant()
            : (strategy == ArbitraryConstantStrategy.LargestRunner
                ? getArbitraryConstantLRBatch(_q_initial)
                : getArbitraryConstantAvgBatch(_q_initial));
        uint128 finalB = strategy == ArbitraryConstantStrategy.Static
            ? getArbitraryConstant()
            : (strategy == ArbitraryConstantStrategy.LargestRunner
                ? getArbitraryConstantLRBatch(_q_final)
                : getArbitraryConstantAvgBatch(_q_final));
        int128 costInitial = _calculateExponentialPriceForOutcome(_q_initial, outcomeIndex, initialB);
        int128 costFinal = _calculateExponentialPriceForOutcome(_q_final, outcomeIndex, finalB);
        cost = costFinal - costInitial;
    }

    function calculateTradeCostBatchForOutcome(uint128[] memory _q_initial, uint128[] memory _q_final, uint256 outcomeIndex, uint128 b) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);

        int128 costInitial = _calculateRatioPriceForOutcome(_q_initial, outcomeIndex, b);
        int128 costFinal = _calculateRatioPriceForOutcome(_q_final, outcomeIndex, b);
        cost = costFinal - costInitial;
    }

    function calculateTradeCostBatchForOutcome(uint128[] memory _q_initial, uint128[] memory _q_final, uint256 outcomeIndex) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);
        int128 costInitial = _calculateRatioPriceForOutcome(_q_initial, outcomeIndex, getArbitraryConstantAvgBatch(_q_initial));
        int128 costFinal = _calculateRatioPriceForOutcome(_q_final, outcomeIndex, getArbitraryConstantAvgBatch(_q_final));
        cost = costFinal - costInitial;
    }

    function calculateTradeCostBatchForOutcome(uint128[] memory _q_initial, uint128[] memory _q_final, uint256 outcomeIndex, ArbitraryConstantStrategy strategy) public pure returns (int128 cost) {
        _validateTradeArrays(_q_initial, _q_final, 2, outcomeIndex);

        uint128 initialB = strategy == ArbitraryConstantStrategy.Static
            ? getArbitraryConstant()
            : (strategy == ArbitraryConstantStrategy.LargestRunner
                ? getArbitraryConstantLRBatch(_q_initial)
                : getArbitraryConstantAvgBatch(_q_initial));
        uint128 finalB = strategy == ArbitraryConstantStrategy.Static
            ? getArbitraryConstant()
            : (strategy == ArbitraryConstantStrategy.LargestRunner
                ? getArbitraryConstantLRBatch(_q_final)
                : getArbitraryConstantAvgBatch(_q_final));
        int128 costInitial = _calculateRatioPriceForOutcome(_q_initial, outcomeIndex, initialB);
        int128 costFinal = _calculateRatioPriceForOutcome(_q_final, outcomeIndex, finalB);
        cost = costFinal - costInitial;
    }

    // Function to calculate the cost of buying additional shares
    function calculateTradeCost(uint128 q1_initial, uint128 q2_initial, uint128 q1_final, uint128 q2_final, uint128 b) public pure returns (int128 cost) {
        cost = calculateTradeCostForOutcome(_pairToArray(q1_initial, q2_initial), _pairToArray(q1_final, q2_final), 0, b);
    }

    function calculateTradeCost(uint128 q1_initial, uint128 q2_initial, uint128 q1_final, uint128 q2_final) public pure returns (int128 cost) {
        cost = calculateTradeCostForOutcome(_pairToArray(q1_initial, q2_initial), _pairToArray(q1_final, q2_final), 0, ArbitraryConstantStrategy.Average);
    }


    /**
     * @notice Calculate trade cost for any N≥2 outcomes (outcome 0, Average strategy)
     * @dev Use calculateTradeCostForOutcome when you need a specific outcome index or strategy.
     * @param _q_initial Array of initial share quantities (length ≥ 2)
     * @param _q_final   Array of final share quantities (same length as _q_initial)
     * @return cost Price delta (final − initial) for outcome 0 as fixed-point 64.64 int128
     */
    function calculateTradeCostN(uint128[] memory _q_initial, uint128[] memory _q_final) public pure returns (int128 cost) {
        cost = calculateTradeCostForOutcome(_q_initial, _q_final, 0, ArbitraryConstantStrategy.Average);
    }

    function calculateTradeCostBatch(uint128[] memory _q_initial, uint128[] memory _q_final) public pure returns (int128 cost) {
        cost = calculateTradeCostBatchForOutcome(_q_initial, _q_final, 0, ArbitraryConstantStrategy.Average);
    }

    function getArbitraryConstantByStrategy(uint128[] memory _qs, ArbitraryConstantStrategy strategy) public pure returns (uint128 b) {
        _validateArrayLength(_qs.length, 2);

        if (strategy == ArbitraryConstantStrategy.Static) {
            b = getArbitraryConstant();
        } else if (strategy == ArbitraryConstantStrategy.LargestRunner) {
            b = getArbitraryConstantLRBatch(_qs);
        } else {
            b = getArbitraryConstantAvgBatch(_qs);
        }
    }

    // Static constant. Could throw an error not recommended for use.
    function getArbitraryConstant() public pure returns (uint128 b) {
        b = uint128(ABDKMath64x64.fromUInt(1_000_000));
    }

    // Dynamic constant based on max value
    function getArbitraryConstantLR(uint128 q1, uint128 q2) public pure returns (uint128 b) {
        b = getArbitraryConstantLRBatch(_pairToArray(q1, q2));
    }

    function getArbitraryConstantLRBatch(uint128[] memory _qs) public pure returns (uint128 b) {
        if (_qs.length < 2 ) {
            revert InvalidInput(InputErrorReason.ArrayTooShort);
        }

        b = _qs[0];
        unchecked {
            for (uint i = 1; i < _qs.length; i++) {
                if (_qs[i] > b) {
                    b = _qs[i];
                }
            }
        }
    }

    // Dynamic constant based on average value
    function getArbitraryConstantAvg(uint128 q1, uint128 q2) public pure returns (uint128 b) {
        b = getArbitraryConstantAvgBatch(_pairToArray(q1, q2));
    }

    function getArbitraryConstantAvgBatch(uint128[] memory _qs) public pure returns (uint128 b) {
        if (_qs.length < 2 ) {
            revert InvalidInput(InputErrorReason.ArrayTooShort);
        }

        unchecked {
            for (uint i = 0; i < _qs.length; i++) {
                b += _qs[i];
            }
            b /= uint128(_qs.length);
        }
    }

    function _calculateExponentialPriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex, uint128 b) internal pure returns (int128 price) {
        int128 denominator;
        int128 numerator;
        int128 b64 = int128(b);

        unchecked {
            for (uint256 i = 0; i < _qs.length; i++) {
                int128 term = ABDKMath64x64.exp(ABDKMath64x64.div(int128(_qs[i]), b64));
                denominator = ABDKMath64x64.add(denominator, term);

                if (i == outcomeIndex) {
                    numerator = term;
                }
            }
        }

        price = ABDKMath64x64.div(numerator, denominator);
    }

    function _calculateRatioPriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex, uint128 b) internal pure returns (int128 price) {
        int128 denominator;
        int128 b64 = int128(b);

        unchecked {
            for (uint256 i = 0; i < _qs.length; i++) {
                denominator = ABDKMath64x64.add(denominator, ABDKMath64x64.div(int128(_qs[i]), b64));
            }
        }

        price = ABDKMath64x64.div(ABDKMath64x64.div(int128(_qs[outcomeIndex]), b64), denominator);
    }

    function _validateTradeArrays(uint256 initialLength, uint256 finalLength, uint256 minLength) internal pure {
        _validateArrayLength(initialLength, minLength);
        if (initialLength != finalLength) {
            revert InvalidInput(InputErrorReason.ArraysLengthMismatch);
        }
    }

    function _validateTradeArrays(uint128[] memory _q_initial, uint128[] memory _q_final, uint256 minLength, uint256 outcomeIndex) internal pure {
        _validateTradeArrays(_q_initial.length, _q_final.length, minLength);
        _validateOutcomeIndex(_q_initial.length, outcomeIndex);
    }

    function _validateOutcomeArray(uint128[] memory _qs, uint256 minLength, uint256 outcomeIndex) internal pure {
        _validateArrayLength(_qs.length, minLength);
        _validateOutcomeIndex(_qs.length, outcomeIndex);
    }

    function _validateArrayLength(uint256 length, uint256 minLength) internal pure {
        if (length < minLength) {
            revert InvalidInput(InputErrorReason.ArrayTooShort);
        }
    }

    function _validateOutcomeIndex(uint256 length, uint256 outcomeIndex) internal pure {
        if (outcomeIndex >= length) {
            revert InvalidOutcomeIndex();
        }
    }

    function _pairToArray(uint128 q1, uint128 q2) internal pure returns (uint128[] memory qs) {
        qs = new uint128[](2);
        qs[0] = q1;
        qs[1] = q2;
    }
}
