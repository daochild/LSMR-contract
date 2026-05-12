import { expect } from "chai";
import hre from "hardhat";

const ONE_64X64 = 2n ** 64n;

describe("LMSR Gas Measurements", function () {
  let ethers;
  let lmsr;

  before(async function () {
    ({ ethers } = await hre.network.create());
    lmsr = await ethers.deployContract("LMSR");
    await lmsr.waitForDeployment();
  });

  // Helper to estimate gas for a contract function call
  async function measureGas(func, args) {
    try {
      const gas = await lmsr[func].estimateGas(...args);
      return gas;
    } catch (e) {
      console.error(`Gas estimation error for ${func}:`, e.message);
      return 0n;
    }
  }

  describe("Pricing - Exponential (Canonical)", function () {
    it("should measure gas for binary pair pricing with explicit b", async function () {
      const qs = [1000n, 800n];
      const b = 900n;

      const gas = await measureGas("calculatePriceForOutcome(uint128[],uint256,uint128)", [qs, 0, b]);

      console.log(`  Binary pair (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for binary pair pricing with Average strategy", async function () {
      const qs = [1000n, 800n];

      const gas = await measureGas("calculatePriceForOutcome(uint128[],uint256)", [qs, 0]);

      console.log(`  Binary pair (Average strategy): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for triple outcome pricing", async function () {
      const qs = [1000n, 800n, 500n];
      const b = 767n;

      const gas = await measureGas("calculatePriceForOutcome(uint128[],uint256,uint128)", [qs, 0, b]);

      console.log(`  Triple (3 outcomes, explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for 4-outcome pricing", async function () {
      const qs = [1000n, 800n, 600n, 400n];
      const b = 700n;

      const gas = await measureGas("calculatePriceForOutcome(uint128[],uint256,uint128)", [qs, 0, b]);

      console.log(`  4-outcome (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for 5-outcome pricing", async function () {
      const qs = [1000n, 800n, 600n, 400n, 200n];
      const b = 600n;

      const gas = await measureGas("calculatePriceForOutcome(uint128[],uint256,uint128)", [qs, 0, b]);

      console.log(`  5-outcome (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for pricing outcome at index 2 in 4-outcome market", async function () {
      const qs = [1000n, 800n, 600n, 400n];
      const b = 700n;

      const gas = await measureGas("calculatePriceForOutcome(uint128[],uint256,uint128)", [qs, 2, b]);

      console.log(`  4-outcome, outcome index 2 (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });
  });

  describe("Pricing - Ratio Linear (Batch)", function () {
    it("should measure gas for binary pair batch pricing with explicit b", async function () {
      const qs = [1000n, 800n];
      const b = 900n;

      const gas = await measureGas("calculatePriceBatchForOutcome(uint128[],uint256,uint128)", [qs, 0, b]);

      console.log(`  Binary pair batch (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for 4-outcome batch pricing", async function () {
      const qs = [1000n, 800n, 600n, 400n];
      const b = 700n;

      const gas = await measureGas("calculatePriceBatchForOutcome(uint128[],uint256,uint128)", [qs, 0, b]);

      console.log(`  4-outcome batch (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for 8-outcome batch pricing", async function () {
      const qs = [1000n, 900n, 800n, 700n, 600n, 500n, 400n, 300n];
      const b = 625n;

      const gas = await measureGas("calculatePriceBatchForOutcome(uint128[],uint256,uint128)", [qs, 0, b]);

      console.log(`  8-outcome batch (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });
  });

  describe("Trade Cost - Exponential", function () {
    it("should measure gas for binary trade cost with explicit b", async function () {
      const initialQs = [1000n, 800n];
      const finalQs = [1100n, 700n];
      const b = 850n;

      const gas = await measureGas("calculateTradeCostForOutcome(uint128[],uint128[],uint256,uint128)", [
        initialQs,
        finalQs,
        0,
        b
      ]);

      console.log(`  Binary trade cost (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for binary trade cost with Average strategy", async function () {
      const initialQs = [1000n, 800n];
      const finalQs = [1100n, 700n];

      const gas = await measureGas("calculateTradeCostForOutcome(uint128[],uint128[],uint256)", [
        initialQs,
        finalQs,
        0
      ]);

      console.log(`  Binary trade cost (Average strategy): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for triple trade cost", async function () {
      const initialQs = [1000n, 800n, 600n];
      const finalQs = [1100n, 700n, 700n];
      const b = 767n;

      const gas = await measureGas("calculateTradeCostForOutcome(uint128[],uint128[],uint256,uint128)", [
        initialQs,
        finalQs,
        0,
        b
      ]);

      console.log(`  Triple trade cost (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for 5-outcome trade cost", async function () {
      const initialQs = [1000n, 800n, 600n, 400n, 200n];
      const finalQs = [1100n, 750n, 600n, 400n, 150n];
      const b = 600n;

      const gas = await measureGas("calculateTradeCostForOutcome(uint128[],uint128[],uint256,uint128)", [
        initialQs,
        finalQs,
        0,
        b
      ]);

      console.log(`  5-outcome trade cost (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });
  });

  describe("Trade Cost - Ratio Linear (Batch)", function () {
    it("should measure gas for binary trade cost batch with explicit b", async function () {
      const initialQs = [1000n, 800n];
      const finalQs = [1100n, 700n];
      const b = 850n;

      const gas = await measureGas("calculateTradeCostBatchForOutcome(uint128[],uint128[],uint256,uint128)", [
        initialQs,
        finalQs,
        0,
        b
      ]);

      console.log(`  Binary trade cost batch (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for 4-outcome trade cost batch", async function () {
      const initialQs = [1000n, 800n, 600n, 400n];
      const finalQs = [1100n, 750n, 550n, 400n];
      const b = 700n;

      const gas = await measureGas("calculateTradeCostBatchForOutcome(uint128[],uint128[],uint256,uint128)", [
        initialQs,
        finalQs,
        0,
        b
      ]);

      console.log(`  4-outcome trade cost batch (explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });
  });

  describe("Arbitrary Constant Strategies", function () {
    it("should measure gas for Static strategy", async function () {
      const qs = [1000n, 800n, 600n];

      const gas = await measureGas("getArbitraryConstantByStrategy(uint128[],uint8)", [qs, 0]); // Static

      console.log(`  Static strategy: ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for LargestRunner strategy on 3 outcomes", async function () {
      const qs = [1000n, 800n, 600n];

      const gas = await measureGas("getArbitraryConstantByStrategy(uint128[],uint8)", [qs, 1]); // LargestRunner

      console.log(`  LargestRunner (3 outcomes): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for LargestRunner strategy on 5 outcomes", async function () {
      const qs = [1000n, 800n, 600n, 400n, 200n];

      const gas = await measureGas("getArbitraryConstantByStrategy(uint128[],uint8)", [qs, 1]); // LargestRunner

      console.log(`  LargestRunner (5 outcomes): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for Average strategy on 3 outcomes", async function () {
      const qs = [1000n, 800n, 600n];

      const gas = await measureGas("getArbitraryConstantAvgBatch(uint128[])", [qs]);

      console.log(`  Average (3 outcomes): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for Average strategy on 5 outcomes", async function () {
      const qs = [1000n, 800n, 600n, 400n, 200n];

      const gas = await measureGas("getArbitraryConstantAvgBatch(uint128[])", [qs]);

      console.log(`  Average (5 outcomes): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });
  });

  describe("Legacy API Compatibility", function () {
    it("should measure gas for legacy calculatePrice", async function () {
      const q1 = 1000n;
      const q2 = 800n;

      const gas = await measureGas("calculatePrice(uint128,uint128)", [q1, q2]);

      console.log(`  Legacy calculatePrice (pair): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for legacy calculatePrice with explicit b", async function () {
      const q1 = 1000n;
      const q2 = 800n;
      const b = 900n;

      const gas = await measureGas("calculatePrice(uint128,uint128,uint128)", [q1, q2, b]);

      console.log(`  Legacy calculatePrice (pair, explicit b): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for legacy calculatePriceTriple", async function () {
      const qs = [1000n, 800n, 600n];

      const gas = await measureGas("calculatePriceTriple(uint128[])", [qs]);

      console.log(`  Legacy calculatePriceTriple: ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for legacy calculatePriceBatch on 4 outcomes", async function () {
      const qs = [1000n, 800n, 600n, 400n];

      const gas = await measureGas("calculatePriceBatch(uint128[])", [qs]);

      console.log(`  Legacy calculatePriceBatch (4 outcomes): ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for legacy calculateTradeCost", async function () {
      const q1_initial = 1000n;
      const q2_initial = 800n;
      const q1_final = 1100n;
      const q2_final = 700n;

      const gas = await measureGas("calculateTradeCost(uint128,uint128,uint128,uint128)", [
        q1_initial,
        q2_initial,
        q1_final,
        q2_final
      ]);

      console.log(`  Legacy calculateTradeCost: ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for legacy calculateTradeCostTriple", async function () {
      const initialQs = [1000n, 800n, 600n];
      const finalQs = [1100n, 700n, 700n];

      const gas = await measureGas("calculateTradeCostTriple(uint128[],uint128[])", [initialQs, finalQs]);

      console.log(`  Legacy calculateTradeCostTriple: ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });

    it("should measure gas for legacy calculateTradeCostBatch", async function () {
      const initialQs = [1000n, 800n, 600n, 400n];
      const finalQs = [1100n, 750n, 550n, 400n];

      const gas = await measureGas("calculateTradeCostBatch(uint128[],uint128[])", [initialQs, finalQs]);

      console.log(`  Legacy calculateTradeCostBatch: ${gas} gas`);
      expect(gas).to.be.greaterThan(0n);
    });
  });

  describe("Scalability Analysis", function () {
    it("should benchmark exponential pricing across different outcome counts", async function () {
      console.log("\n    Exponential Pricing Scalability (with explicit b):");

      for (let count = 2; count <= 10; count++) {
        const qs = Array(count).fill(0).map((_, i) => BigInt(1000 - i * 100));
        const b = BigInt(Math.floor(qs.reduce((a, b) => Number(a) + Number(b)) / count));

        const gas = await measureGas("calculatePriceForOutcome(uint128[],uint256,uint128)", [qs, 0, b]);

        console.log(`      ${count} outcomes: ${gas} gas`);
      }
    });

    it("should benchmark batch pricing across different outcome counts", async function () {
      console.log("\n    Batch (Ratio) Pricing Scalability (with explicit b):");

      for (let count = 2; count <= 10; count++) {
        const qs = Array(count).fill(0).map((_, i) => BigInt(1000 - i * 100));
        const b = BigInt(Math.floor(qs.reduce((a, b) => Number(a) + Number(b)) / count));

        const gas = await measureGas("calculatePriceBatchForOutcome(uint128[],uint256,uint128)", [qs, 0, b]);

        console.log(`      ${count} outcomes: ${gas} gas`);
      }
    });

    it("should benchmark Average strategy computation across different outcome counts", async function () {
      console.log("\n    Average Strategy Computation Scalability:");

      for (let count = 2; count <= 10; count++) {
        const qs = Array(count).fill(0).map((_, i) => BigInt(1000 - i * 100));

        const gas = await measureGas("getArbitraryConstantAvgBatch(uint128[])", [qs]);

        console.log(`      ${count} outcomes: ${gas} gas`);
      }
    });
  });
});

