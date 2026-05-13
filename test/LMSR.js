import { expect } from "chai";
import hre from "hardhat";

const ONE_64X64 = 2n ** 64n;

describe("LMSR", function () {
  let ethers;

  before(async function () {
    ({ ethers } = await hre.network.create());
  });

  async function deployLMSR() {
    const lmsr = await ethers.deployContract("LMSR");
    await lmsr.waitForDeployment();
    return lmsr;
  }

  it("keeps pair pricing wrappers aligned with the canonical outcome API", async function () {
    const lmsr = await deployLMSR();
    const qs = [10, 20];
    const b = 15;

    const explicitWrapper = await lmsr["calculatePrice(uint128,uint128,uint128)"](qs[0], qs[1], b);
    const explicitCanonical = await lmsr["calculatePriceForOutcome(uint128[],uint256,uint128)"](qs, 0, b);
    const averageWrapper = await lmsr["calculatePrice(uint128,uint128)"](qs[0], qs[1]);
    const averageCanonical = await lmsr["calculatePriceForOutcome(uint128[],uint256,uint8)"](qs, 0, 2);

    expect(explicitCanonical).to.equal(explicitWrapper);
    expect(averageCanonical).to.equal(averageWrapper);
  });

  it("supports explicit outcome selection for generic exponential pricing", async function () {
    const lmsr = await deployLMSR();
    const qs = [10, 20, 30];
    const b = 20;

    const price0 = await lmsr["calculatePriceForOutcome(uint128[],uint256,uint128)"](qs, 0, b);
    const price1 = await lmsr["calculatePriceForOutcome(uint128[],uint256,uint128)"](qs, 1, b);
    const price2 = await lmsr["calculatePriceForOutcome(uint128[],uint256,uint128)"](qs, 2, b);

    const total = price0 + price1 + price2;
    expect(total >= ONE_64X64 - 2n).to.equal(true);
    expect(total <= ONE_64X64 + 2n).to.equal(true);
    // calculatePriceN with same inputs should equal price of outcome 0
    expect(await lmsr.calculatePriceN(qs)).to.equal(price0);
  });

  it("keeps batch pricing wrappers aligned with explicit outcome helpers", async function () {
    const lmsr = await deployLMSR();
    const qs = [15, 10, 5, 20];

    const wrapper = await lmsr.calculatePriceBatch(qs);
    const canonical = await lmsr["calculatePriceBatchForOutcome(uint128[],uint256,uint8)"](qs, 0, 2);
    const secondOutcome = await lmsr["calculatePriceBatchForOutcome(uint128[],uint256,uint8)"](qs, 1, 2);

    expect(canonical).to.equal(wrapper);
    expect(secondOutcome).to.not.equal(wrapper);
  });

  it("keeps pair trade-cost wrappers aligned with the canonical outcome API", async function () {
    const lmsr = await deployLMSR();
    const initialQs = [10, 20];
    const finalQs = [15, 18];
    const b = 12;

    const explicitWrapper = await lmsr["calculateTradeCost(uint128,uint128,uint128,uint128,uint128)"](
      initialQs[0], initialQs[1], finalQs[0], finalQs[1], b
    );
    const explicitCanonical = await lmsr["calculateTradeCostForOutcome(uint128[],uint128[],uint256,uint128)"](
      initialQs, finalQs, 0, b
    );
    const averageWrapper = await lmsr["calculateTradeCost(uint128,uint128,uint128,uint128)"](
      initialQs[0], initialQs[1], finalQs[0], finalQs[1]
    );
    const averageCanonical = await lmsr["calculateTradeCostForOutcome(uint128[],uint128[],uint256,uint8)"](
      initialQs, finalQs, 0, 2
    );

    expect(explicitCanonical).to.equal(explicitWrapper);
    expect(averageCanonical).to.equal(averageWrapper);
  });

  it("makes arbitrary-constant strategy explicit for canonical pricing", async function () {
    const lmsr = await deployLMSR();
    const qs = [7, 11, 13];
    const largestRunnerB = await lmsr.getArbitraryConstantLRBatch(qs);

    const byStrategy = await lmsr["calculatePriceForOutcome(uint128[],uint256,uint8)"](qs, 0, 1);
    const byExplicitB = await lmsr["calculatePriceForOutcome(uint128[],uint256,uint128)"](qs, 0, largestRunnerB);

    expect(byStrategy).to.equal(byExplicitB);
  });

  it("rejects out-of-range outcome indices", async function () {
    const lmsr = await deployLMSR();

    await expect(
      lmsr["calculatePriceForOutcome(uint128[],uint256)"]([10, 20], 2)
    ).to.be.revertedWithCustomError(lmsr, "InvalidOutcomeIndex");
  });

  // ========== calculatePriceN tests ==========

  it("calculatePriceN matches calculatePrice for 2 outcomes", async function () {
    const lmsr = await deployLMSR();
    const qs = [10n, 20n];

    const priceN      = await lmsr.calculatePriceN(qs);
    const priceLegacy = await lmsr["calculatePrice(uint128,uint128)"](qs[0], qs[1]);

    expect(priceN).to.equal(priceLegacy);
  });

  it("calculatePriceN works for 4 and 5 outcomes", async function () {
    const lmsr = await deployLMSR();
    const qs4 = [10n, 20n, 30n, 40n];
    const qs5 = [10n, 20n, 30n, 40n, 50n];

    const price4 = await lmsr.calculatePriceN(qs4);
    const price5 = await lmsr.calculatePriceN(qs5);

    expect(price4).to.be.gt(0n);
    expect(price5).to.be.gt(0n);
    // More outcomes with higher total shares → lower price for outcome 0
    expect(price5).to.be.lt(price4);
  });

  it("calculatePriceN rejects arrays shorter than 2", async function () {
    const lmsr = await deployLMSR();

    await expect(lmsr.calculatePriceN([10n]))
      .to.be.revertedWithCustomError(lmsr, "InvalidInput")
      .withArgs(0); // ArrayTooShort
  });

  // ========== calculateTradeCostN tests ==========

  it("calculateTradeCostN matches calculateTradeCost for 2 outcomes", async function () {
    const lmsr = await deployLMSR();
    const qi = [10n, 20n];
    const qf = [15n, 18n];

    const costN      = await lmsr.calculateTradeCostN(qi, qf);
    const costLegacy = await lmsr["calculateTradeCost(uint128,uint128,uint128,uint128)"](
      qi[0], qi[1], qf[0], qf[1]
    );

    expect(costN).to.equal(costLegacy);
  });

  it("calculateTradeCostN works for 4, 5, 10 outcomes", async function () {
    const lmsr = await deployLMSR();

    // Buy shares only in outcome 0 — price changes asymmetrically so cost ≠ 0
    for (const n of [4, 5, 10]) {
      const qi = Array.from({length: n}, (_, i) => BigInt(i + 1) * 10n);
      const qf = qi.map((v, i) => i === 0 ? v + 100n : v);
      const cost = await lmsr.calculateTradeCostN(qi, qf);
      expect(cost).to.not.equal(0n, `N=${n} trade cost should be non-zero`);
    }
  });

  it("calculateTradeCostN rejects mismatched array lengths", async function () {
    const lmsr = await deployLMSR();

    await expect(lmsr.calculateTradeCostN([10n, 20n, 30n], [10n, 20n]))
      .to.be.revertedWithCustomError(lmsr, "InvalidInput")
      .withArgs(1); // ArraysLengthMismatch
  });
});
