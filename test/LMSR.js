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

    const explicitWrapper = await lmsr["calculatePrice(uint128,uint128,uint128)"](
      qs[0],
      qs[1],
      b
    );
    const explicitCanonical = await lmsr[
      "calculatePriceForOutcome(uint128[],uint256,uint128)"
    ](qs, 0, b);
    const averageWrapper = await lmsr["calculatePrice(uint128,uint128)"](
      qs[0],
      qs[1]
    );
    const averageCanonical = await lmsr[
      "calculatePriceForOutcome(uint128[],uint256,uint8)"
    ](qs, 0, 2);

    expect(explicitCanonical).to.equal(explicitWrapper);
    expect(averageCanonical).to.equal(averageWrapper);
  });

  it("supports explicit outcome selection for generic exponential pricing", async function () {
    const lmsr = await deployLMSR();
    const qs = [10, 20, 30];
    const b = 20;

    const price0 = await lmsr[
      "calculatePriceForOutcome(uint128[],uint256,uint128)"
    ](qs, 0, b);
    const price1 = await lmsr[
      "calculatePriceForOutcome(uint128[],uint256,uint128)"
    ](qs, 1, b);
    const price2 = await lmsr[
      "calculatePriceForOutcome(uint128[],uint256,uint128)"
    ](qs, 2, b);

    const total = price0 + price1 + price2;

    expect(total >= ONE_64X64 - 2n).to.equal(true);
    expect(total <= ONE_64X64 + 2n).to.equal(true);
    expect(
      await lmsr.calculatePriceTriple(qs)
    ).to.equal(price0);
  });

  it("keeps batch pricing wrappers aligned with explicit outcome helpers", async function () {
    const lmsr = await deployLMSR();
    const qs = [15, 10, 5, 20];

    const wrapper = await lmsr.calculatePriceBatch(qs);
    const canonical = await lmsr[
      "calculatePriceBatchForOutcome(uint128[],uint256,uint8)"
    ](qs, 0, 2);
    const secondOutcome = await lmsr[
      "calculatePriceBatchForOutcome(uint128[],uint256,uint8)"
    ](qs, 1, 2);

    expect(canonical).to.equal(wrapper);
    expect(secondOutcome).to.not.equal(wrapper);
  });

  it("keeps pair trade-cost wrappers aligned with the canonical outcome API", async function () {
    const lmsr = await deployLMSR();
    const initialQs = [10, 20];
    const finalQs = [15, 18];
    const b = 12;

    const explicitWrapper = await lmsr[
      "calculateTradeCost(uint128,uint128,uint128,uint128,uint128)"
    ](initialQs[0], initialQs[1], finalQs[0], finalQs[1], b);
    const explicitCanonical = await lmsr[
      "calculateTradeCostForOutcome(uint128[],uint128[],uint256,uint128)"
    ](initialQs, finalQs, 0, b);
    const averageWrapper = await lmsr[
      "calculateTradeCost(uint128,uint128,uint128,uint128)"
    ](initialQs[0], initialQs[1], finalQs[0], finalQs[1]);
    const averageCanonical = await lmsr[
      "calculateTradeCostForOutcome(uint128[],uint128[],uint256,uint8)"
    ](initialQs, finalQs, 0, 2);

    expect(explicitCanonical).to.equal(explicitWrapper);
    expect(averageCanonical).to.equal(averageWrapper);
  });

  it("makes arbitrary-constant strategy explicit for canonical pricing", async function () {
    const lmsr = await deployLMSR();
    const qs = [7, 11, 13];
    const largestRunnerB = await lmsr.getArbitraryConstantLRBatch(qs);

    const byStrategy = await lmsr[
      "calculatePriceForOutcome(uint128[],uint256,uint8)"
    ](qs, 0, 1);
    const byExplicitB = await lmsr[
      "calculatePriceForOutcome(uint128[],uint256,uint128)"
    ](qs, 0, largestRunnerB);

    expect(byStrategy).to.equal(byExplicitB);
  });

  it("rejects out-of-range outcome indices", async function () {
    const lmsr = await deployLMSR();

    await expect(
      lmsr["calculatePriceForOutcome(uint128[],uint256)"]([10, 20], 2)
    ).to.be.revertedWithCustomError(lmsr, "InvalidOutcomeIndex");
  });

  it("fixes triple trade-cost validation to require three outcomes", async function () {
    const lmsr = await deployLMSR();

    await expect(
      lmsr.calculateTradeCostTriple([10, 20], [11, 19])
    )
      .to.be.revertedWithCustomError(lmsr, "InvalidInput")
      .withArgs(0);
  });
});

