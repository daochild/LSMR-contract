# Agent Guide for LSMR-contract

## Project Snapshot
- Single-contract Hardhat project focused on LMSR pricing math for prediction-market style shares.
- Core logic lives in `contracts/LMSR.sol`; there are currently no additional contracts, scripts, or tests.
- Math primitives come from `abdk-libraries-solidity/ABDKMath64x64.sol` (fixed-point `int128` operations).
- Tooling is minimal: Hardhat + `@nomicfoundation/hardhat-toolbox` with TypeScript config (`hardhat.config.ts`).

## Architecture and Data Flow
- External callers invoke pure functions on `LMSR` to compute prices and trade costs; no storage/state mutation exists.
- Public API is organized by market size:
  - Pair: `calculatePrice(q1,q2[,b])`, `calculateTradeCost(...)`
  - Triple: `calculatePriceTriple(uint128[] memory _qs)`, `calculateTradeCostTriple(...)`
  - Batch/N outcomes: `calculatePriceBatch(...)`, `calculateTradeCostBatch(...)`
- Constant `b` can be supplied directly or derived by helpers (`getArbitraryConstant*`).
- Input validation uses custom error `InvalidInput(InputErrorReason)` with enum values:
  - `ArrayTooShort`
  - `ArraysLengthMismatch`

## Project-Specific Coding Patterns
- The contract uses overloaded function names heavily (same name, different signatures). Preserve signatures when extending APIs.
- Batch/triple functions enforce minimum array lengths before math; follow this pattern for any new array-based method.
- Existing trade-cost functions compute `cost_final - cost_initial` from price functions rather than separate formulas.
- `calculatePriceBatch` currently uses ratios of `(q_i / b)` terms (not exponentials), unlike pair/triple methods; treat this as intentional current behavior unless explicitly changing semantics.
- Helper methods are grouped by `b` strategy:
  - static (`getArbitraryConstant`)
  - largest-runner (`getArbitraryConstantLR*`)
  - average (`getArbitraryConstantAvg*`)

## Developer Workflows
- Install dependencies from project root:
  - `npm install`
- Compile contract:
  - `npm run build` (maps to `npx hardhat compile`)
- Run test suite:
  - `npm test` (maps to `npx hardhat test`)
- Solidity version for compilation is pinned in `hardhat.config.ts` to `0.8.24` while `LMSR.sol` pragma is `^0.8.4`; keep new contracts compatible with compiler setting.

## Integration and Dependency Notes
- External dependency surface is intentionally small:
  - Runtime Solidity math lib: `abdk-libraries-solidity`
  - Dev stack: Hardhat toolbox only
- No on-chain token/account integrations exist yet; current contract is a pure math engine suitable for off-chain simulation or as a base contract.
- If adding scripts/tests, use Hardhat defaults (`test/`, `scripts/`) to match toolbox conventions not yet customized in this repo.

## Key Files to Read First
- `contracts/LMSR.sol` - all domain logic, validation, and helper strategies.
- `hardhat.config.ts` - compiler/toolchain baseline.
- `package.json` - canonical build/test commands.
- `README.md` - brief project intent (prediction market, LMSR).

