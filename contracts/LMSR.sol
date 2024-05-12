// SPDX-License-Identifier: ISC
pragma solidity ^0.8.4;

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

/**
 * @title LMSR - Logarithmic Market Scoring Rule
 * @dev LMSR contract to calculate the price of a share based on the number of outstanding shares
 * @notice price calculated only for q1 or _qs[0]
 *
 * @author Pavlo Bolhar <paul.bolhar@gmail.com>
 */
contract LMSR {
    using ABDKMath64x64 for int128;

    enum InputErrorReason {
        ArrayTooShort,
        ArraysLengthMismatch
    }

    error InvalidInput(InputErrorReason);

    // Equation: price = e^(q1/b) / (e^(q1/b) + e^(q2/b))
    //
    // In this formula, b is an arbitrary constant, q1 is the number of outstanding
    // shares in the stock for which you're calculating the price,
    // and q2 is the number of outstanding shares in the other stock. e - logarithm
    // Function to calculate the price based on q1, q2, and b
    function calculatePrice(uint128 q1, uint128 q2, uint128 b) public pure returns (int128 price) {
        int128 e_q1_over_b = ABDKMath64x64.exp(ABDKMath64x64.div(int128(q1), int128(b)));
        int128 e_q2_over_b = ABDKMath64x64.exp(ABDKMath64x64.div(int128(q2), int128(b)));

        int128 denominator = ABDKMath64x64.add(e_q1_over_b, e_q2_over_b);
        price = ABDKMath64x64.div(e_q1_over_b, denominator);
    }

    function calculatePrice(uint128 q1, uint128 q2) public pure returns (int128 price) {
        uint128 b = getArbitraryConstantAvg(q1, q2);
        int128 e_q1_over_b = ABDKMath64x64.exp(ABDKMath64x64.div(int128(q1), int128(b)));
        int128 e_q2_over_b = ABDKMath64x64.exp(ABDKMath64x64.div(int128(q2), int128(b)));

        int128 denominator = ABDKMath64x64.add(e_q1_over_b, e_q2_over_b);
        price = ABDKMath64x64.div(e_q1_over_b, denominator);
    }

    function calculatePriceTriple(uint128[] memory _qs) public pure returns (int128 price) {
        if (_qs.length < 3) {
            revert InvalidInput(InputErrorReason.ArrayTooShort);
        }

        int128 b = int128(getArbitraryConstantAvgBatch(_qs));
        int128 e_q1_over_b = ABDKMath64x64.exp(ABDKMath64x64.div(int128(_qs[0]), b));
        int128 e_q2_over_b = ABDKMath64x64.exp(ABDKMath64x64.div(int128(_qs[1]), b));
        int128 e_q3_over_b = ABDKMath64x64.exp(ABDKMath64x64.div(int128(_qs[2]), b));

        int128 denominator = ABDKMath64x64.add(e_q1_over_b, e_q2_over_b);
        denominator = ABDKMath64x64.add(denominator, e_q3_over_b);
        price = ABDKMath64x64.div(e_q1_over_b, denominator);
    }

    // price of q1
    function calculatePriceBatch(uint128[] memory _qs) public pure returns (int128 price) {
        if (_qs.length < 2) {
            revert InvalidInput(InputErrorReason.ArrayTooShort);
        }

        int128 b = int128(getArbitraryConstantAvgBatch(_qs));
        int128 denominator;
        for (uint256 i; i < _qs.length; i++) {
            denominator = ABDKMath64x64.add(denominator, ABDKMath64x64.div(int128(_qs[i]), b));
        }

        price = ABDKMath64x64.div(ABDKMath64x64.div(int128(_qs[0]), b), denominator);
    }

    // Function to calculate the cost of buying additional shares
    function calculateTradeCost(uint128 q1_initial, uint128 q2_initial, uint128 q1_final, uint128 q2_final, uint128 b) public pure returns (int128 cost) {
        int128 cost_initial = calculatePrice(q1_initial, q2_initial, b);
        int128 cost_final = calculatePrice(q1_final, q2_final, b);

        cost = cost_final - cost_initial;
    }

    function calculateTradeCost(uint128 q1_initial, uint128 q2_initial, uint128 q1_final, uint128 q2_final) public pure returns (int128 cost) {
        uint128 b = getArbitraryConstantAvg(q1_initial, q2_initial);
        int128 cost_initial = calculatePrice(q1_initial, q2_initial, b);
        b = getArbitraryConstantAvg(q1_final, q2_final);
        int128 cost_final = calculatePrice(q1_final, q2_final, b);

        cost = cost_final - cost_initial;
    }

    function calculateTradeCostTriple(uint128[] memory _q_initial, uint128[] memory _q_final) public pure returns (int128 cost) {
        if (_q_initial.length < 2 ) {
            revert InvalidInput(InputErrorReason.ArrayTooShort);
        }
        if (_q_initial.length != _q_final.length) {
            revert InvalidInput(InputErrorReason.ArraysLengthMismatch);
        }

        uint128 b = getArbitraryConstantAvgBatch(_q_initial);
        int128 cost_initial = calculatePriceTriple(_q_initial);
        b = getArbitraryConstantAvgBatch(_q_final);
        int128 cost_final = calculatePriceTriple(_q_final);

        cost = cost_final - cost_initial;
    }

    function calculateTradeCostBatch(uint128[] memory _q_initial, uint128[] memory _q_final) public pure returns (int128 cost) {
        if (_q_initial.length < 2 ) {
            revert InvalidInput(InputErrorReason.ArrayTooShort);
        }
        if (_q_initial.length != _q_final.length) {
            revert InvalidInput(InputErrorReason.ArraysLengthMismatch);
        }

        uint128 b = getArbitraryConstantAvgBatch(_q_initial);
        int128 cost_initial = calculatePriceBatch(_q_initial);
        b = getArbitraryConstantAvgBatch(_q_final);
        int128 cost_final = calculatePriceBatch(_q_final);

        cost = cost_final - cost_initial;
    }

    // Static constant. Could throw an error not recommended for use.
    function getArbitraryConstant() public pure returns (uint128 b) {
        b = uint128(ABDKMath64x64.fromUInt(1_000_000));
    }

    // Dynamic constant based on max value
    function getArbitraryConstantLR(uint128 q1, uint128 q2) public pure returns (uint128 b) {
        b = q1 > q2 ? q1 : q2;
    }

    function getArbitraryConstantLRBatch(uint128[] memory _qs) public pure returns (uint128 b) {
        if (_qs.length < 2 ) {
            revert InvalidInput(InputErrorReason.ArrayTooShort);
        }

        b = _qs[0];
        for (uint i = 1; i < _qs.length; i++) {
            if (_qs[i] > b) {
                b = _qs[i];
            }
        }
    }

    // Dynamic constant based on average value
    function getArbitraryConstantAvg(uint128 q1, uint128 q2) public pure returns (uint128 b) {
        b = (q1 + q2) / 2;
    }

    function getArbitraryConstantAvgBatch(uint128[] memory _qs) public pure returns (uint128 b) {
        if (_qs.length < 2 ) {
            revert InvalidInput(InputErrorReason.ArrayTooShort);
        }

        for (uint i; i < _qs.length; i++) {
            b += _qs[i];
        }

        b /= uint128(_qs.length);
    }
}
