# Agent Guide for LSMR-contract

## Project Snapshot
- Hardhat math-engine project for LMSR pricing used in prediction-market style share calculations.
- Core business logic lives in `contracts/LMSR.sol`; `contracts/ILMSR.sol` defines the public API surface as an interface.
- Fixed-point math depends on `abdk-libraries-solidity/ABDKMath64x64.sol`, so public results are mostly `int128` 64.64 values rather than plain integers.
- Tooling is intentionally small: `hardhat` + `@nomicfoundation/hardhat-toolbox-mocha-ethers`, TypeScript config, and `forge-std` for Solidity test sources compiled under Hardhat.

## Architecture and Data Flow
- External callers use pure methods only: inputs are outstanding share counts, outputs are share prices or trade-cost deltas.
- The current API provides two tiers:
  - **Outcome-based canonical methods**: `calculatePriceForOutcome(uint128[] memory _qs, uint256 outcomeIndex, [uint128 b | ArbitraryConstantStrategy])`, `calculateTradeCostForOutcome(...)`, and batch variants (`calculatePriceBatchForOutcome`, `calculateTradeCostBatchForOutcome`). These make the priced outcome explicit and accept `b` either directly or via strategy selection.
  - **Legacy shape-based wrappers** (for backwards compatibility): pair (`calculatePrice(q1, q2[, b])`, `calculateTradeCost(...)`), N-outcome exponential wrappers (`calculatePriceN`, `calculateTradeCostN`), and batch/N-outcome ratio wrappers (`calculatePriceBatch(...)`, `calculateTradeCostBatch(...)`). These all hardcode `outcomeIndex = 0` and default to `ArbitraryConstantStrategy.Average`.
- `b` can be provided directly as `uint128` or derived via `ArbitraryConstantStrategy`: `Static` (`getArbitraryConstant`), `LargestRunner` (`getArbitraryConstantLR*`), or `Average` (`getArbitraryConstantAvg*`). The strategy parameter is accepted directly in outcome-based methods.
- Input validation uses the custom errors: `InvalidInput(InputErrorReason)` with `ArrayTooShort` and `ArraysLengthMismatch`, and `InvalidOutcomeIndex()` when the outcome index exceeds array bounds.

## Project-Specific Patterns
- **Outcome-based methods are canonical**: New code should prefer `calculatePriceForOutcome`, `calculateTradeCostForOutcome` and their batch variants. These make the priced outcome explicit and document intent more clearly than implicit first-outcome indexing.
- Legacy wrappers (`calculatePrice`, `calculatePriceN`, `calculatePriceBatch`, `calculateTradeCost`, `calculateTradeCostN`, etc.) are maintained for backwards compatibility and convenience; they call the outcome-based methods with `outcomeIndex = 0` and strategy `Average` as defaults.
- Preserve overloaded public signatures when extending the contract; existing integrations may rely on them.
- Strategy selection is now explicit: outcome-based methods accept `ArbitraryConstantStrategy` (or `uint128 b` directly) as a parameter. Do not hide strategy logic inside overload resolution; the caller should specify which strategy they want.
- New array-based business methods should validate lengths and outcome indices before delegating into pricing math, mirroring the pattern in `calculatePriceForOutcome`, `calculateTradeCostForOutcome`, and their batch variants.
- Existing trade-cost methods compute `cost_final - cost_initial` by calling price methods twice (once at initial state, once at final state) instead of using a separate closed-form cost equation. When strategy selection is used, both initial and final states compute their own `b` values dynamically.
- `calculatePriceBatch` and `calculatePriceBatchForOutcome` compute prices using `(q_i / b)` ratio sums ("linear" pricing), whereas exponential methods sum `e^(q_i/b)` exponents. Do not mix these semantics; clarify in comments which pricing model applies.
- Validation helper: `_validateOutcomeIndex(length, outcomeIndex)` raises `InvalidOutcomeIndex()` if `outcomeIndex >= length`.

## Current API Status and Future Evolution
- **Refactor complete**: Canonical outcome-based methods (`calculatePriceForOutcome`, `calculateTradeCostForOutcome`, and batch variants) are now established. Strategy selection via `ArbitraryConstantStrategy` enum is explicit in the interface.
- Legacy shape-based wrappers remain as **compatibility layers** for backwards compatibility; they are thin wrappers that call the outcome-based methods with sensible defaults.
- **Testing existing coverage**: When modifying pricing logic or validation, verify that legacy wrappers (e.g., `calculatePrice`, `calculatePriceN`, `calculatePriceBatch`, `calculateTradeCost`, `calculateTradeCostN`) still produce identical results for the first outcome as direct calls to the outcome-based canonical methods.
- **Future extensions**: If new pricing models, strategies, or market shapes are added, define outcome-based canonical methods first, then layer legacy-compatible wrappers on top.

## Developer Workflows
- Install dependencies from the repo root with `npm install`.
- Compile with `npm run build` (`npx hardhat compile`).
- Run tests with `npm test` (`npx hardhat test`); current suite includes JavaScript tests in `test/` and Solidity tests in `contracts/LMSR.t.sol`.
- `hardhat.config.ts` currently compiles with Solidity `0.8.20`, while contracts declare `pragma solidity ^0.8.0`; keep new contracts/features compatible with the configured compiler.

## Integration Notes
- Runtime dependency surface is only `abdk-libraries-solidity`; all other packages are dev tooling.
- No token transfers, ownership, oracle reads, or market settlement flows exist yet; this repository is a pure math engine.
- If you add tests or scripts, use Hardhat defaults (`test/`, `scripts/`) because the repo does not define custom paths.

## Read First
- `contracts/LMSR.sol` - all pricing logic, validation behavior, strategy selection, and both outcome-based canonical methods and legacy shape-based wrappers. The contract uses an enum `ArbitraryConstantStrategy` with `Static`, `LargestRunner`, and `Average` variants.
- `contracts/ILMSR.sol` - interface-level source of truth for function signatures, overloads, custom errors, and API docs.
- `hardhat.config.ts` - compiler version and toolchain baseline.
- `package.json` - authoritative build/test commands and plugins.
- `README.md` - usage examples and pricing model descriptions.
