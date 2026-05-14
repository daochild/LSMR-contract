/**
 * LMSR vs LMSRAssembly – Gas Comparison
 *
 * For every representative call this test:
 *   1. Asserts both contracts return the IDENTICAL result (correctness guard).
 *   2. Estimates gas for each and prints a side-by-side Markdown table.
 *
 * Run: npm test -- --grep "Gas Comparison"
 */
import { expect } from "chai";
import hre from "hardhat";
const COL_METHOD = 56;
const COL_GAS    = 10;
const COL_ASM    = 13;
const COL_DELTA  =  9;
const COL_PCT    =  7;
function padL(s, n) { return String(s).padStart(n); }
function padR(s, n) { return String(s).padEnd(n); }
function tableHeader() {
  return [
    `| ${ padR("Method", COL_METHOD) }| ${ padL("LMSR gas", COL_GAS) } | ${ padL("Assembly gas", COL_ASM) } | ${ padL("Delta", COL_DELTA) } | ${ padL("Δ%", COL_PCT) } |`,
    `|${ "-".repeat(COL_METHOD+1) }|${ "-".repeat(COL_GAS+2) }|${ "-".repeat(COL_ASM+2) }|${ "-".repeat(COL_DELTA+2) }|${ "-".repeat(COL_PCT+2) }|`,
  ].join("\n");
}
function tableRow(label, gasA, gasB) {
  const delta   = gasA - gasB;
  const pct     = gasA === 0n ? "  n/a" : (Number(delta * 10000n / gasA) / 100).toFixed(2) + "%";
  const deltaStr = delta === 0n ? "0" : (delta > 0n ? "-" : "+") + (delta < 0n ? -delta : delta);
  return `| ${ padR(label, COL_METHOD) }| ${ padL(gasA, COL_GAS) } | ${ padL(gasB, COL_ASM) } | ${ padL(deltaStr, COL_DELTA) } | ${ padL(pct, COL_PCT) } |`;
}
function sectionRow(title) {
  const w = COL_METHOD + COL_GAS + COL_ASM + COL_DELTA + COL_PCT + 14;
  return `| ${ title.slice(0, w-2).padEnd(w-2) }|`;
}
describe("LMSR vs LMSRAssembly – Gas Comparison", function () {
  let ethers, lmsr, lmsrAsm;
  const rows = [];
  before(async function () {
    ({ ethers } = await hre.network.create());
    lmsr    = await ethers.deployContract("LMSR");
    await lmsr.waitForDeployment();
    lmsrAsm = await ethers.deployContract("LMSRAssembly");
    await lmsrAsm.waitForDeployment();
  });
  async function cmp(label, sig, args) {
    const gasA    = await lmsr   [sig].estimateGas(...args);
    const gasB    = await lmsrAsm[sig].estimateGas(...args);
    const resultA = await lmsr   [sig](...args);
    const resultB = await lmsrAsm[sig](...args);
    expect(resultB.toString()).to.equal(resultA.toString(), `${label}: result mismatch`);
    rows.push(tableRow(label, gasA, gasB));
    return { gasA, gasB };
  }
  it("compares arbitrary-constant helpers", async function () {
    rows.push(sectionRow("── Arbitrary-constant helpers ──────────────────────────────────────────────────────────────"));
    const qs2 = [1000n, 800n];
    const qs5 = [1000n, 800n, 600n, 400n, 200n];
    await cmp("getArbitraryConstant()",             "getArbitraryConstant()",                    []);
    await cmp("getArbitraryConstantLR(q1,q2)",      "getArbitraryConstantLR(uint128,uint128)",    qs2);
    await cmp("getArbitraryConstantAvg(q1,q2)",     "getArbitraryConstantAvg(uint128,uint128)",   qs2);
    await cmp("getArbitraryConstantLRBatch([2])",   "getArbitraryConstantLRBatch(uint128[])",     [qs2]);
    await cmp("getArbitraryConstantAvgBatch([2])",  "getArbitraryConstantAvgBatch(uint128[])",    [qs2]);
    await cmp("getArbitraryConstantLRBatch([5])",   "getArbitraryConstantLRBatch(uint128[])",     [qs5]);
    await cmp("getArbitraryConstantAvgBatch([5])",  "getArbitraryConstantAvgBatch(uint128[])",    [qs5]);
  });
  it("compares exponential pricing", async function () {
    rows.push(sectionRow("── Exponential pricing ──────────────────────────────────────────────────────────────────────"));
    const qs2 = [1000n, 800n];
    const qs3 = [1000n, 800n, 500n];
    const qs5 = [1000n, 800n, 600n, 400n, 200n];
    const qs8 = [1000n,900n,800n,700n,600n,500n,400n,300n];
    const qs10= Array.from({length:10}, (_,i)=>BigInt(1000-i*80));
    await cmp("calculatePrice(q1,q2,b)  [2-out, explicit b]",  "calculatePrice(uint128,uint128,uint128)",              [...qs2, 900n]);
    await cmp("calculatePrice(q1,q2)    [2-out, avg]",         "calculatePrice(uint128,uint128)",                     qs2);
    await cmp("calculatePriceForOutcome([2], explicit b)",     "calculatePriceForOutcome(uint128[],uint256,uint128)",  [qs2, 0, 900n]);
    await cmp("calculatePriceForOutcome([2], avg strategy)",   "calculatePriceForOutcome(uint128[],uint256)",          [qs2, 0]);
    await cmp("calculatePriceForOutcome([2], LR strategy)",    "calculatePriceForOutcome(uint128[],uint256,uint8)",    [qs2, 0, 1]);
    await cmp("calculatePriceN([3])",                          "calculatePriceN(uint128[])",                          [qs3]);
    await cmp("calculatePriceForOutcome([3], explicit b)",     "calculatePriceForOutcome(uint128[],uint256,uint128)",  [qs3, 0, 767n]);
    await cmp("calculatePriceN([5])",                          "calculatePriceN(uint128[])",                          [qs5]);
    await cmp("calculatePriceForOutcome([5], explicit b)",     "calculatePriceForOutcome(uint128[],uint256,uint128)",  [qs5, 0, 600n]);
    await cmp("calculatePriceForOutcome([8], explicit b)",     "calculatePriceForOutcome(uint128[],uint256,uint128)",  [qs8, 0, 625n]);
    await cmp("calculatePriceForOutcome([10], explicit b)",    "calculatePriceForOutcome(uint128[],uint256,uint128)",  [qs10,0, 560n]);
  });
  it("compares ratio (batch) pricing", async function () {
    rows.push(sectionRow("── Ratio (batch linear) pricing ─────────────────────────────────────────────────────────────"));
    const qs2 = [1000n, 800n];
    const qs5 = [1000n, 800n, 600n, 400n, 200n];
    const qs8 = [1000n,900n,800n,700n,600n,500n,400n,300n];
    await cmp("calculatePriceBatch([2])",                        "calculatePriceBatch(uint128[])",                          [qs2]);
    await cmp("calculatePriceBatchForOutcome([2], explicit b)",  "calculatePriceBatchForOutcome(uint128[],uint256,uint128)", [qs2, 0, 900n]);
    await cmp("calculatePriceBatch([5])",                        "calculatePriceBatch(uint128[])",                          [qs5]);
    await cmp("calculatePriceBatchForOutcome([5], explicit b)",  "calculatePriceBatchForOutcome(uint128[],uint256,uint128)", [qs5, 0, 600n]);
    await cmp("calculatePriceBatchForOutcome([8], explicit b)",  "calculatePriceBatchForOutcome(uint128[],uint256,uint128)", [qs8, 0, 625n]);
  });
  it("compares exponential trade cost", async function () {
    rows.push(sectionRow("── Trade cost (exponential) ─────────────────────────────────────────────────────────────────"));
    const qi2 = [1000n, 800n],  qf2 = [1100n, 700n];
    const qi5 = [1000n,800n,600n,400n,200n], qf5 = [1100n,750n,600n,400n,150n];
    await cmp("calculateTradeCost(pair,b)      [2-out]",        "calculateTradeCost(uint128,uint128,uint128,uint128,uint128)", [...qi2,...qf2,850n]);
    await cmp("calculateTradeCost(pair,avg)    [2-out]",        "calculateTradeCost(uint128,uint128,uint128,uint128)",         [...qi2,...qf2]);
    await cmp("calculateTradeCostForOutcome([2], explicit b)",  "calculateTradeCostForOutcome(uint128[],uint128[],uint256,uint128)", [qi2,qf2,0,850n]);
    await cmp("calculateTradeCostForOutcome([2], avg)",         "calculateTradeCostForOutcome(uint128[],uint128[],uint256)",   [qi2,qf2,0]);
    await cmp("calculateTradeCostN([5])",                       "calculateTradeCostN(uint128[],uint128[])",                    [qi5,qf5]);
    await cmp("calculateTradeCostForOutcome([5], explicit b)",  "calculateTradeCostForOutcome(uint128[],uint128[],uint256,uint128)", [qi5,qf5,0,600n]);
  });
  it("compares ratio trade cost", async function () {
    rows.push(sectionRow("── Trade cost (ratio / batch) ───────────────────────────────────────────────────────────────"));
    const qi2=[1000n,800n], qf2=[1100n,700n];
    const qi5=[1000n,800n,600n,400n,200n], qf5=[1100n,750n,600n,400n,150n];
    await cmp("calculateTradeCostBatch([2])",                       "calculateTradeCostBatch(uint128[],uint128[])",                             [qi2,qf2]);
    await cmp("calculateTradeCostBatch([5])",                       "calculateTradeCostBatch(uint128[],uint128[])",                             [qi5,qf5]);
    await cmp("calculateTradeCostBatchForOutcome([5], explicit b)", "calculateTradeCostBatchForOutcome(uint128[],uint128[],uint256,uint128)",    [qi5,qf5,0,600n]);
  });
  it("prints scalability table (N = 2..12 outcomes)", async function () {
    const expRows   = [];
    const ratioRows = [];
    for (const n of [2,3,4,5,6,8,10,12]) {
      const qs  = Array.from({length:n}, (_,i)=>BigInt(Math.max(50, 1000-i*50)));
      const b   = qs.reduce((a,v)=>a+v,0n) / BigInt(n);
      const lbl = `N=${String(n).padStart(2)}`;
      const [gExpA,gExpB,rExpA,rExpB] = await Promise.all([
        lmsr   ["calculatePriceForOutcome(uint128[],uint256,uint128)"].estimateGas(qs,0,b),
        lmsrAsm["calculatePriceForOutcome(uint128[],uint256,uint128)"].estimateGas(qs,0,b),
        lmsr   ["calculatePriceForOutcome(uint128[],uint256,uint128)"](qs,0,b),
        lmsrAsm["calculatePriceForOutcome(uint128[],uint256,uint128)"](qs,0,b),
      ]);
      expect(rExpB.toString()).to.equal(rExpA.toString(), `Exp N=${n}: mismatch`);
      expRows.push(tableRow(`calculatePriceForOutcome (exp)   ${lbl}`, gExpA, gExpB));
      const [gRatA,gRatB,rRatA,rRatB] = await Promise.all([
        lmsr   ["calculatePriceBatchForOutcome(uint128[],uint256,uint128)"].estimateGas(qs,0,b),
        lmsrAsm["calculatePriceBatchForOutcome(uint128[],uint256,uint128)"].estimateGas(qs,0,b),
        lmsr   ["calculatePriceBatchForOutcome(uint128[],uint256,uint128)"](qs,0,b),
        lmsrAsm["calculatePriceBatchForOutcome(uint128[],uint256,uint128)"](qs,0,b),
      ]);
      expect(rRatB.toString()).to.equal(rRatA.toString(), `Ratio N=${n}: mismatch`);
      ratioRows.push(tableRow(`calculatePriceBatchForOutcome (ratio) ${lbl}`, gRatA, gRatB));
    }
    console.log("\n  Scalability – Exponential pricing");
    console.log(tableHeader());
    expRows.forEach(r => console.log(r));
    console.log("\n  Scalability – Ratio (batch) pricing");
    console.log(tableHeader());
    ratioRows.forEach(r => console.log(r));
  });
  // Print the full accumulated table after all sub-tests pass
  after(function () {
    console.log("\n\n  ══════════════ Complete Gas Comparison ══════════════");
    console.log(tableHeader());
    rows.forEach(r => console.log(r));
    console.log("\n  All results verified identical between LMSR and LMSRAssembly ✓\n");
  });
});
