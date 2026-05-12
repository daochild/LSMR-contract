# Agent Guide for LSMR-contract

## Project Snapshot
- Single-contract Hardhat project for LMSR pricing math used in prediction-market style share calculations.
- All business logic lives in `contracts/LMSR.sol`; there is no storage, deployment script, frontend, or second contract yet.
- Fixed-point math depends on `abdk-libraries-solidity/ABDKMath64x64.sol`, so public results are mostly `int128` 64.64 values rather than plain integers.
- Tooling is intentionally small: `hardhat`, `@nomicfoundation/hardhat-toolbox`, TypeScript config, and no custom plugins.

## Architecture and Data Flow
- External callers use pure methods only: inputs are outstanding share counts, outputs are share prices or trade-cost deltas.
- The current API is split by market shape:
  - pair: `calculatePrice(q1, q2[, b])`, `calculateTradeCost(...)`
  - triple: `calculatePriceTriple(uint128[] memory)`, `calculateTradeCostTriple(...)`
  - batch/N-outcome: `calculatePriceBatch(...)`, `calculateTradeCostBatch(...)`
- "Price" always means the first outcome (`q1` or `_qs[0]`); this first-outcome convention is important when reviewing interface changes.
- `b` can be provided directly or derived by helper families: static (`getArbitraryConstant`), max-runner (`getArbitraryConstantLR*`), or average (`getArbitraryConstantAvg*`).
- Input validation uses the custom error `InvalidInput(InputErrorReason)` with `ArrayTooShort` and `ArraysLengthMismatch`.

## Project-Specific Patterns
- Preserve overloaded public signatures when extending the contract; existing integrations may rely on them.
- New array-based business methods should validate lengths before delegating into pricing math, matching the pattern used in `calculatePriceTriple`, `calculatePriceBatch`, and the `getArbitraryConstant*Batch` helpers.
- Existing trade-cost methods compute `cost_final - cost_initial` by calling price methods twice instead of using a separate closed-form cost equation.
- `calculatePriceBatch` intentionally differs from pair/triple math today: it sums `(q_i / b)` ratios instead of exponentials. Treat that as current behavior unless the task explicitly changes pricing semantics.
- There is a known interface inconsistency in `calculateTradeCostTriple`: it only checks for length `>= 2`, while `calculatePriceTriple` requires `>= 3`. Fix validation if you touch that path.

## Current Interface Refactor Guidance
- Prefer canonical methods that make the priced outcome explicit (for example, an `outcomeIndex`) instead of relying on the implicit first-outcome rule.
- Keep existing `calculatePrice*` / `calculateTradeCost*` entry points as compatibility wrappers when adding clearer business-facing APIs.
- If you introduce strategy selection for `b`, make the choice explicit in the interface rather than hiding it inside overload resolution.
- When changing the API surface, add tests that prove old wrappers still match the new canonical implementation for the first outcome.

## Developer Workflows
- Install dependencies from the repo root with `npm install`.
- Compile with `npm run build` (`npx hardhat compile`).
- Run tests with `npm test` (`npx hardhat test`). Current baseline may report "No contracts to compile" and run only Solidity tests if no JS/TS tests exist.
- `hardhat.config.ts` currently compiles with Solidity `0.8.20`, while `contracts/LMSR.sol` declares `pragma solidity ^0.8.4`; keep new contracts/features compatible with the configured compiler.

## Integration Notes
- Runtime dependency surface is only `abdk-libraries-solidity`; all other packages are dev tooling.
- No token transfers, ownership, oracle reads, or market settlement flows exist yet; this repository is a pure math engine.
- If you add tests or scripts, use Hardhat defaults (`test/`, `scripts/`) because the repo does not define custom paths.

## Read First
- `contracts/LMSR.sol` - all pricing logic, validation behavior, and `b` helper strategies.
- `hardhat.config.ts` - compiler version and toolchain baseline.
- `package.json` - authoritative build/test commands.
- `README.md` - minimal project intent.

