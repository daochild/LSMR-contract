# LSMR-contract

A Solidity implementation of the **Logarithmic Market Scoring Rule (LMSR)** for pricing prediction market shares. This contract computes share prices and trade costs based on outstanding share quantities using fixed-point arithmetic.

## Overview

LMSR is a cost-function-based market maker that determines prices based on the total quantities of shares outstanding for each outcome. It's designed to incentivize accurate probability estimates in prediction markets by maintaining a constant liquidity pool.

### Key Concepts

- **Shares**: Each outcome has an outstanding quantity (`q_i` representing how many shares of that outcome are held).
- **Price**: The probability expressed as a fixed-point ratio (64.64 bit format via ABDKMath64x64). For a binary market, `price(q1) + price(q2) ≈ 1.0`.
- **Arbitrary Constant (`b`)**: A scaling factor that controls price sensitivity. Higher `b` values make prices flatter; lower values create steeper curves. Can be chosen via strategy (Static, LargestRunner, or Average).
- **Trade Cost**: The price difference between two states, computed as `cost_atFinal - cost_atInitial`.

## Installation

```bash
# Clone the repository
git clone https://github.com/user/LSMR-contract.git
cd LSMR-contract

# Install dependencies
npm install
```

## Building and Testing

```bash
# Compile the contract
npm run build

# Run tests
npm test
```

## Usage

### 1. Getting Share Prices

#### For a specific outcome (recommended):

```solidity
import {LMSR} from "./contracts/LMSR.sol";

contract MyMarket {
    LMSR public lmsr;
    
    function getPriceForOutcome(uint128[] memory quantities, uint256 outcomeIndex) external view returns (int128) {
        // Calculate price using Average strategy for b
        return lmsr.calculatePriceForOutcome(quantities, outcomeIndex);
    }
    
    function getPriceWithCustomB(uint128[] memory quantities, uint256 outcomeIndex, uint128 b) external view returns (int128) {
        // Calculate price with explicit b value
        return lmsr.calculatePriceForOutcome(quantities, outcomeIndex, b);
    }
}
```

#### For legacy API (backwards compatible):

```solidity
// Binary market pricing
int128 price = lmsr.calculatePrice(q1, q2);  // Uses Average strategy

// Triple market
int128 price = lmsr.calculatePriceTriple(quantities);  // quantities[0] is priced

// N-outcome market (linear pricing)
int128 price = lmsr.calculatePriceBatch(quantities);  // quantities[0] is priced
```

### 2. Computing Trade Costs

```solidity
// Cost to trade from initial quantities to final quantities
int128 cost = lmsr.calculateTradeCostForOutcome(
    initialQuantities,
    finalQuantities,
    outcomeIndex
);

// Or with legacy API
int128 cost = lmsr.calculateTradeCost(
    q1_initial, q2_initial,
    q1_final, q2_final
);
```

### 3. Selecting the Arbitrary Constant Strategy

The `ArbitraryConstantStrategy` enum controls how `b` is derived:

```solidity
enum ArbitraryConstantStrategy {
    Static,       // Fixed constant (1,000,000)
    LargestRunner, // Largest q_i (most aggressive pricing)
    Average       // Average of all q_i (balanced)
}

// Pass strategy directly to outcome-based methods
int128 price = lmsr.calculatePriceForOutcome(quantities, 0, ArbitraryConstantStrategy.LargestRunner);

// Or compute b directly
uint128 b = lmsr.getArbitraryConstantByStrategy(quantities, ArbitraryConstantStrategy.Average);
```

### 4. Understanding the Two API Tiers

**Outcome-based (canonical, recommended for new code):**
- `calculatePriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex, [uint128 b | ArbitraryConstantStrategy])`
- `calculateTradeCostForOutcome(...)`
- `calculatePriceBatchForOutcome(...)` – uses linear pricing (`q_i / b` ratios)
- Makes the priced outcome explicit; strategy is a parameter, not implicit

**Legacy shape-based (backwards compatible):**
- `calculatePrice(q1, q2)`, `calculatePriceTriple(uint128[])`, `calculatePriceBatch(...)`
- All hardcode `outcomeIndex = 0` and use `ArbitraryConstantStrategy.Average`
- Useful for existing integrations

## Pricing Models

The contract implements two pricing models:

1. **Exponential Pricing** (canonical, used in `calculatePriceForOutcome`):
   ```
   price = e^(q_i/b) / Σ(e^(q_j/b))
   ```
   Reflects traditional LMSR cost functions; convex curves.

2. **Ratio Pricing** ("linear", used in `calculatePriceBatch*`):
   ```
   price = (q_i/b) / Σ(q_j/b)
   ```
   Simplified linear model; better for certain market designs.

Do not mix these semantics—choose based on your market's requirements.

## Example: Binary Market

```javascript
// In tests or scripts using ethers.js
const quantities = [ethers.toBigInt(1000), ethers.toBigInt(800)];
const outcomeIndex = 0;

// Get price for outcome 0
const price = await lmsr.calculatePriceForOutcome(quantities, outcomeIndex);
console.log("Price (64.64 fixed-point):", price.toString());

// Compute trade cost: buy 200 more shares of outcome 0
const newQuantities = [ethers.toBigInt(1200), ethers.toBigInt(800)];
const cost = await lmsr.calculateTradeCostForOutcome(quantities, newQuantities, outcomeIndex);
console.log("Trade cost:", cost.toString());
```

## Fixed-Point Arithmetic

All returned prices and costs are **64.64 fixed-point integers** (type `int128`), not floats. 

- `1.0` in 64.64 format = `0x10000000000000000` (2^64 as int128)
- To convert to decimal: divide by 2^64
- The ABDK library handles all math; results are always in this format

## Development Notes

- **No state**: This is a pure math engine—all methods are `pure` or `view`.
- **Fixed compiler**: Solidity 0.8.20 via Hardhat.
- **Only runtime dependency**: `abdk-libraries-solidity` for fixed-point arithmetic.
- **Validation**: Raises `InvalidInput(reason)` for short arrays, `InvalidOutcomeIndex()` for out-of-bounds indices.

## License

ISC
