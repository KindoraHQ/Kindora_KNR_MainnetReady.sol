const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time, setBalance } = require("@nomicfoundation/hardhat-network-helpers");

describe("Kindora Token - Comprehensive Test Suite", function () {
  let token;
  let router;
  let pair;
  let owner;
  let user1;
  let user2;
  let charityWallet;
  let deadAddress;

  const TOTAL_SUPPLY = ethers.parseEther("10000000"); // 10M tokens
  const SWAP_THRESHOLD = (TOTAL_SUPPLY * 5n) / 10000n; // 0.05% of supply
  const MAX_TX = (TOTAL_SUPPLY * 2n) / 100n; // 2% of supply
  const MAX_WALLET = (TOTAL_SUPPLY * 2n) / 100n; // 2% of supply
  const BUY_COOLDOWN_SECONDS = 10;

  beforeEach(async function () {
    [owner, user1, user2, charityWallet] = await ethers.getSigners();

    // Deploy mock router
    const MockRouter = await ethers.getContractFactory("MockRouter");
    router = await MockRouter.deploy();
    await router.waitForDeployment();

    // Fund router with ETH for simulating swaps
    await owner.sendTransaction({
      to: await router.getAddress(),
      value: ethers.parseEther("100")
    });

    // Deploy Kindora token
    const Kindora = await ethers.getContractFactory("Kindora");
    token = await Kindora.deploy(await router.getAddress());
    await token.waitForDeployment();

    // Get pair address
    pair = await token.pair();
    deadAddress = await token.deadAddress();

    // Set charity wallet before enabling trading
    await token.setCharityWallet(charityWallet.address);
  });

  describe("ERC20 Basic Functionality", function () {
    it("Should have correct name", async function () {
      expect(await token.name()).to.equal("Kindora");
    });

    it("Should have correct symbol", async function () {
      expect(await token.symbol()).to.equal("KNR");
    });

    it("Should have correct decimals", async function () {
      expect(await token.decimals()).to.equal(18);
    });

    it("Should have correct total supply", async function () {
      expect(await token.totalSupply()).to.equal(TOTAL_SUPPLY);
    });

    it("Should assign total supply to owner", async function () {
      expect(await token.balanceOf(owner.address)).to.equal(TOTAL_SUPPLY);
    });

    it("Should approve tokens correctly", async function () {
      const approveAmount = ethers.parseEther("1000");
      await expect(token.approve(user1.address, approveAmount))
        .to.emit(token, "Approval")
        .withArgs(owner.address, user1.address, approveAmount);
      
      expect(await token.allowance(owner.address, user1.address)).to.equal(approveAmount);
    });

    it("Should transfer tokens correctly", async function () {
      await token.enableTrading();
      const transferAmount = ethers.parseEther("1000");
      
      await expect(token.transfer(user1.address, transferAmount))
        .to.emit(token, "Transfer")
        .withArgs(owner.address, user1.address, transferAmount);
      
      expect(await token.balanceOf(user1.address)).to.equal(transferAmount);
    });

    it("Should handle transferFrom correctly", async function () {
      await token.enableTrading();
      const approveAmount = ethers.parseEther("1000");
      const transferAmount = ethers.parseEther("500");
      
      await token.approve(user1.address, approveAmount);
      
      await expect(token.connect(user1).transferFrom(owner.address, user2.address, transferAmount))
        .to.emit(token, "Transfer")
        .withArgs(owner.address, user2.address, transferAmount);
      
      expect(await token.balanceOf(user2.address)).to.equal(transferAmount);
      expect(await token.allowance(owner.address, user1.address)).to.equal(approveAmount - transferAmount);
    });

    it("Should revert transferFrom when exceeding allowance", async function () {
      const approveAmount = ethers.parseEther("100");
      const transferAmount = ethers.parseEther("200");
      
      await token.approve(user1.address, approveAmount);
      
      await expect(
        token.connect(user1).transferFrom(owner.address, user2.address, transferAmount)
      ).to.be.revertedWith("ERC20: transfer exceeds allowance");
    });

    it("Should revert on zero amount transfer", async function () {
      await token.enableTrading();
      await expect(token.transfer(user1.address, 0)).to.be.revertedWith("Zero amount");
    });

    it("Should revert on transfer to zero address", async function () {
      await token.enableTrading();
      await expect(
        token.transfer(ethers.ZeroAddress, ethers.parseEther("100"))
      ).to.be.revertedWith("ERC20: transfer to zero");
    });

    it("Should revert on approve to zero address", async function () {
      await expect(
        token.approve(ethers.ZeroAddress, ethers.parseEther("100"))
      ).to.be.revertedWith("ERC20: approve to zero");
    });
  });

  describe("Ownership and Access Control", function () {
    it("Should have correct initial owner", async function () {
      expect(await token.owner()).to.equal(owner.address);
    });

    it("Should allow owner to renounce ownership after trading enabled", async function () {
      await token.enableTrading();
      await token.renounceOwnership();
      expect(await token.owner()).to.equal(ethers.ZeroAddress);
    });

    it("Should revert renounce ownership if trading not enabled", async function () {
      await expect(token.renounceOwnership()).to.be.revertedWith("Trading not enabled");
    });

    it("Should revert onlyOwner functions when called by non-owner", async function () {
      await expect(
        token.connect(user1).setSwapEnabled(false)
      ).to.be.revertedWith("Not owner");

      await expect(
        token.connect(user1).setCooldownEnabled(false)
      ).to.be.revertedWith("Not owner");

      await expect(
        token.connect(user1).enableTrading()
      ).to.be.revertedWith("Not owner");
    });
  });

  describe("Trading Enable/Disable", function () {
    it("Should enable trading correctly", async function () {
      await expect(token.enableTrading())
        .to.emit(token, "TradingEnabled");
      
      expect(await token.tradingEnabled()).to.be.true;
      expect(await token.charityWalletLocked()).to.be.true;
    });

    it("Should revert enabling trading without charity wallet set", async function () {
      const MockRouter2 = await ethers.getContractFactory("MockRouter");
      const router2 = await MockRouter2.deploy();
      const Kindora2 = await ethers.getContractFactory("Kindora");
      const token2 = await Kindora2.deploy(await router2.getAddress());
      
      await expect(token2.enableTrading()).to.be.revertedWith("Set charity wallet first");
    });

    it("Should revert enabling trading twice", async function () {
      await token.enableTrading();
      await expect(token.enableTrading()).to.be.revertedWith("Trading already enabled");
    });

    it("Should block transfers for non-excluded addresses when trading not enabled", async function () {
      await token.transfer(user1.address, ethers.parseEther("1000"));
      
      await expect(
        token.connect(user1).transfer(user2.address, ethers.parseEther("500"))
      ).to.be.revertedWith("Trading not enabled");
    });

    it("Should allow excluded addresses to transfer when trading not enabled", async function () {
      const transferAmount = ethers.parseEther("1000");
      await token.transfer(user1.address, transferAmount);
      expect(await token.balanceOf(user1.address)).to.equal(transferAmount);
    });
  });

  describe("Wallet-to-Wallet Transfers (No Tax)", function () {
    beforeEach(async function () {
      await token.enableTrading();
    });

    it("Should not apply tax on wallet-to-wallet transfers", async function () {
      const transferAmount = ethers.parseEther("1000");
      await token.transfer(user1.address, transferAmount);
      
      expect(await token.balanceOf(user1.address)).to.equal(transferAmount);
    });

    it("Should handle multiple wallet-to-wallet transfers without tax", async function () {
      await token.transfer(user1.address, ethers.parseEther("1000"));
      
      await token.connect(user1).transfer(user2.address, ethers.parseEther("100"));
      await token.connect(user1).transfer(user2.address, ethers.parseEther("200"));
      await token.connect(user1).transfer(user2.address, ethers.parseEther("300"));
      
      expect(await token.balanceOf(user2.address)).to.equal(ethers.parseEther("600"));
      expect(await token.balanceOf(user1.address)).to.equal(ethers.parseEther("400"));
    });
  });

  describe("Buy Transactions (5% Tax)", function () {
    beforeEach(async function () {
      await token.enableTrading();
      // Transfer tokens to pair to simulate liquidity
      await token.transfer(pair, ethers.parseEther("100000"));
      // Fund pair with ETH for gas when impersonated
      await setBalance(pair, ethers.parseEther("100"));
    });

    it("Should apply 5% tax on buys", async function () {
      // Advance time to avoid cooldown
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const buyAmount = ethers.parseEther("10000");
      const expectedTax = (buyAmount * 5n) / 100n; // 5%
      const expectedBurn = (buyAmount * 1n) / 100n; // 1%
      const expectedContract = expectedTax - expectedBurn; // 4%
      const expectedReceived = buyAmount - expectedTax; // 95%
      
      // Simulate buy: pair transfers to user1
      await token.connect(await ethers.getImpersonatedSigner(pair)).transfer(user1.address, buyAmount);
      
      expect(await token.balanceOf(user1.address)).to.equal(expectedReceived);
      expect(await token.balanceOf(deadAddress)).to.equal(expectedBurn);
      expect(await token.balanceOf(await token.getAddress())).to.equal(expectedContract);
    });

    it("Should emit TokensBurned event on buy", async function () {
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const buyAmount = ethers.parseEther("10000");
      const burnAmount = (buyAmount * 1n) / 100n;
      
      const pairSigner = await ethers.getImpersonatedSigner(pair);
      await expect(token.connect(pairSigner).transfer(user1.address, buyAmount))
        .to.emit(token, "TokensBurned")
        .withArgs(burnAmount);
    });

    it("Should correctly distribute tax on buy", async function () {
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const buyAmount = ethers.parseEther("20000");
      const pairSigner = await ethers.getImpersonatedSigner(pair);
      
      await token.connect(pairSigner).transfer(user1.address, buyAmount);
      
      // 1% burn = 200 tokens
      // 4% to contract = 800 tokens
      // 95% to buyer = 19,000 tokens
      expect(await token.balanceOf(user1.address)).to.equal(ethers.parseEther("19000"));
      expect(await token.balanceOf(deadAddress)).to.equal(ethers.parseEther("200"));
      expect(await token.balanceOf(await token.getAddress())).to.equal(ethers.parseEther("800"));
    });
  });

  describe("Sell Transactions (5% Tax + SwapBack)", function () {
    beforeEach(async function () {
      await token.enableTrading();
    });

    it("Should apply 5% tax on sells", async function () {
      const userBalance = ethers.parseEther("50000");
      await token.transfer(user1.address, userBalance);
      
      const deadBalanceBefore = await token.balanceOf(deadAddress);
      const sellAmount = ethers.parseEther("10000");
      
      await token.connect(user1).transfer(pair, sellAmount);
      
      const expectedTax = (sellAmount * 5n) / 100n;
      const expectedBurn = (sellAmount * 1n) / 100n;
      const expectedReceived = sellAmount - expectedTax;
      
      expect(await token.balanceOf(pair)).to.equal(expectedReceived);
      expect(await token.balanceOf(deadAddress)).to.equal(deadBalanceBefore + expectedBurn);
    });

    it("Should trigger swapBack when threshold is met", async function () {
      // Configure router to return BNB on swaps
      await router.setSwapBNBMultiplier(ethers.parseUnits("1", 9)); // 0.001 BNB per token
      
      // Transfer enough tokens to contract to meet threshold
      await token.transfer(await token.getAddress(), SWAP_THRESHOLD * 2n);
      
      // Transfer to user and sell to trigger swapBack
      await token.transfer(user1.address, ethers.parseEther("10000"));
      
      const contractBalanceBefore = await token.balanceOf(await token.getAddress());
      
      await token.connect(user1).transfer(pair, ethers.parseEther("10000"));
      
      // Contract should have swapped back
      expect(await token.balanceOf(await token.getAddress())).to.be.lt(contractBalanceBefore);
    });
  });

  describe("SwapBack Mechanism", function () {
    beforeEach(async function () {
      await token.enableTrading();
      await router.setSwapBNBMultiplier(ethers.parseUnits("1", 9));
    });

    it("Should swap tokens and add liquidity", async function () {
      await token.transfer(await token.getAddress(), SWAP_THRESHOLD * 2n);
      await token.transfer(user1.address, ethers.parseEther("10000"));
      
      await token.connect(user1).transfer(pair, ethers.parseEther("10000"));
      
      // Verify router was called
      expect(await router.lastSwapAmountIn()).to.be.gt(0);
    });

    it("Should send BNB to charity wallet", async function () {
      const charityBalanceBefore = await ethers.provider.getBalance(charityWallet.address);
      
      await token.transfer(await token.getAddress(), SWAP_THRESHOLD * 2n);
      await token.transfer(user1.address, ethers.parseEther("10000"));
      
      await token.connect(user1).transfer(pair, ethers.parseEther("10000"));
      
      const charityBalanceAfter = await ethers.provider.getBalance(charityWallet.address);
      expect(charityBalanceAfter).to.be.gte(charityBalanceBefore);
    });

    it("Should handle charity transfer failure gracefully", async function () {
      // Deploy rejecting receiver
      const RejectingReceiver = await ethers.getContractFactory("RejectingReceiver");
      const rejectingCharity = await RejectingReceiver.deploy();
      
      // Deploy new token with rejecting charity
      const MockRouter2 = await ethers.getContractFactory("MockRouter");
      const router2 = await MockRouter2.deploy();
      await owner.sendTransaction({
        to: await router2.getAddress(),
        value: ethers.parseEther("10")
      });
      
      const Kindora2 = await ethers.getContractFactory("Kindora");
      const token2 = await Kindora2.deploy(await router2.getAddress());
      
      await token2.setCharityWallet(await rejectingCharity.getAddress());
      await token2.enableTrading();
      await router2.setSwapBNBMultiplier(ethers.parseUnits("1", 9));
      
      const threshold = (await token2.totalSupply() * 5n) / 10000n;
      await token2.transfer(await token2.getAddress(), threshold * 2n);
      await token2.transfer(user1.address, ethers.parseEther("10000"));
      
      // Should not revert even if charity transfer fails
      await token2.connect(user1).transfer(await token2.pair(), ethers.parseEther("10000"));
      
      // Rejecting charity should not have received BNB
      expect(await ethers.provider.getBalance(await rejectingCharity.getAddress())).to.equal(0);
    });
  });

  describe("Anti-Whale Protection", function () {
    beforeEach(async function () {
      await token.enableTrading();
      // Fund pair with ETH for gas when impersonated
      await setBalance(pair, ethers.parseEther("100"));
    });

    it("Should enforce maxTxAmount on buys", async function () {
      await token.transfer(pair, TOTAL_SUPPLY / 2n);
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const buyAmount = MAX_TX + 1n;
      const pairSigner = await ethers.getImpersonatedSigner(pair);
      
      await expect(
        token.connect(pairSigner).transfer(user1.address, buyAmount)
      ).to.be.revertedWith("Buy exceeds maxTx");
    });

    it("Should enforce maxTxAmount on sells", async function () {
      const sellAmount = MAX_TX + 1n;
      await token.transfer(user2.address, sellAmount);
      
      await expect(
        token.connect(user2).transfer(pair, sellAmount)
      ).to.be.revertedWith("Sell exceeds maxTx");
    });

    it("Should enforce maxWalletAmount on buys", async function () {
      await token.transfer(pair, TOTAL_SUPPLY / 2n);
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const pairSigner = await ethers.getImpersonatedSigner(pair);
      await token.connect(pairSigner).transfer(user1.address, MAX_WALLET / 2n);
      
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const currentBalance = await token.balanceOf(user1.address);
      const buyAmount = MAX_WALLET - currentBalance + ethers.parseEther("1000");
      
      if (buyAmount <= MAX_TX) {
        await expect(
          token.connect(pairSigner).transfer(user1.address, buyAmount)
        ).to.be.revertedWith("Exceeds maxWallet");
      }
    });

    it("Should enforce maxWalletAmount on transfers", async function () {
      await token.transfer(user1.address, MAX_WALLET);
      await token.transfer(user2.address, MAX_WALLET / 2n);
      
      const transferAmount = (MAX_WALLET / 2n) + ethers.parseEther("1000");
      
      await expect(
        token.connect(user1).transfer(user2.address, transferAmount)
      ).to.be.revertedWith("Exceeds maxWallet");
    });

    it("Should allow excluded addresses to bypass limits", async function () {
      // Deploy new token for this test since we need to set exclusions before trading
      const MockRouter2 = await ethers.getContractFactory("MockRouter");
      const router2 = await MockRouter2.deploy();
      await owner.sendTransaction({
        to: await router2.getAddress(),
        value: ethers.parseEther("10")
      });
      
      const Kindora2 = await ethers.getContractFactory("Kindora");
      const token2 = await Kindora2.deploy(await router2.getAddress());
      const pair2 = await token2.pair();
      
      await token2.setCharityWallet(charityWallet.address);
      await token2.setExcludedFromLimits(user1.address, true);
      await token2.enableTrading();
      
      await token2.transfer(pair2, TOTAL_SUPPLY / 2n);
      await setBalance(pair2, ethers.parseEther("100"));
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const buyAmount = MAX_TX * 2n;
      const pairSigner = await ethers.getImpersonatedSigner(pair2);
      
      await token2.connect(pairSigner).transfer(user1.address, buyAmount);
      expect(await token2.balanceOf(user1.address)).to.be.gt(0);
    });

    it("Should allow owner to loosen maxTx after launch", async function () {
      await token.setMaxTxAmount(MAX_TX + 1n);
      expect(await token.maxTxAmount()).to.equal(MAX_TX + 1n);
    });

    it("Should prevent tightening maxTx after launch", async function () {
      await expect(
        token.setMaxTxAmount(MAX_TX - 1n)
      ).to.be.revertedWith("Can only loosen after launch");
    });

    it("Should allow owner to loosen maxWallet after launch", async function () {
      await token.setMaxWalletAmount(MAX_WALLET + 1n);
      expect(await token.maxWalletAmount()).to.equal(MAX_WALLET + 1n);
    });

    it("Should prevent tightening maxWallet after launch", async function () {
      await expect(
        token.setMaxWalletAmount(MAX_WALLET - 1n)
      ).to.be.revertedWith("Can only loosen after launch");
    });
  });

  describe("Buy Cooldown", function () {
    beforeEach(async function () {
      await token.enableTrading();
      await token.transfer(pair, TOTAL_SUPPLY / 2n);
      // Fund pair with ETH for gas when impersonated
      await setBalance(pair, ethers.parseEther("100"));
    });

    it("Should enforce cooldown on consecutive buys", async function () {
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const buyAmount = ethers.parseEther("1000");
      const pairSigner = await ethers.getImpersonatedSigner(pair);
      
      await token.connect(pairSigner).transfer(user1.address, buyAmount);
      
      await expect(
        token.connect(pairSigner).transfer(user1.address, buyAmount)
      ).to.be.revertedWith("Buy cooldown active");
    });

    it("Should allow buy after cooldown period", async function () {
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const buyAmount = ethers.parseEther("1000");
      const pairSigner = await ethers.getImpersonatedSigner(pair);
      
      await token.connect(pairSigner).transfer(user1.address, buyAmount);
      
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      await token.connect(pairSigner).transfer(user1.address, buyAmount);
      
      // Each buy: 1000 * 95% = 950 tokens
      expect(await token.balanceOf(user1.address)).to.equal(ethers.parseEther("1900"));
    });

    it("Should not apply cooldown to excluded addresses", async function () {
      // Deploy new token for this test since we need to set exclusions before trading
      const MockRouter2 = await ethers.getContractFactory("MockRouter");
      const router2 = await MockRouter2.deploy();
      await owner.sendTransaction({
        to: await router2.getAddress(),
        value: ethers.parseEther("10")
      });
      
      const Kindora2 = await ethers.getContractFactory("Kindora");
      const token2 = await Kindora2.deploy(await router2.getAddress());
      const pair2 = await token2.pair();
      
      await token2.setCharityWallet(charityWallet.address);
      await token2.setExcludedFromLimits(user1.address, true);
      await token2.enableTrading();
      await token2.transfer(pair2, TOTAL_SUPPLY / 2n);
      
      await setBalance(pair2, ethers.parseEther("100"));
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const buyAmount = ethers.parseEther("1000");
      const pairSigner = await ethers.getImpersonatedSigner(pair2);
      
      await token2.connect(pairSigner).transfer(user1.address, buyAmount);
      await token2.connect(pairSigner).transfer(user1.address, buyAmount);
      
      expect(await token2.balanceOf(user1.address)).to.be.gt(buyAmount);
    });

    it("Should allow disabling cooldown", async function () {
      await token.setCooldownEnabled(false);
      
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const buyAmount = ethers.parseEther("1000");
      const pairSigner = await ethers.getImpersonatedSigner(pair);
      
      await token.connect(pairSigner).transfer(user1.address, buyAmount);
      await token.connect(pairSigner).transfer(user1.address, buyAmount);
      
      expect(await token.balanceOf(user1.address)).to.be.gt(buyAmount);
    });
  });

  describe("Charity Wallet Management", function () {
    it("Should set charity wallet correctly", async function () {
      const MockRouter2 = await ethers.getContractFactory("MockRouter");
      const router2 = await MockRouter2.deploy();
      const Kindora2 = await ethers.getContractFactory("Kindora");
      const token2 = await Kindora2.deploy(await router2.getAddress());
      
      await expect(token2.setCharityWallet(user1.address))
        .to.emit(token2, "CharityWalletSet")
        .withArgs(user1.address);
      
      expect(await token2.charityWallet()).to.equal(user1.address);
    });

    it("Should lock charity wallet after trading enabled", async function () {
      await token.enableTrading();
      expect(await token.charityWalletLocked()).to.be.true;
      
      await expect(
        token.setCharityWallet(user1.address)
      ).to.be.revertedWith("Charity wallet locked");
    });

    it("Should revert setting zero address as charity wallet", async function () {
      const MockRouter2 = await ethers.getContractFactory("MockRouter");
      const router2 = await MockRouter2.deploy();
      const Kindora2 = await ethers.getContractFactory("Kindora");
      const token2 = await Kindora2.deploy(await router2.getAddress());
      
      await expect(
        token2.setCharityWallet(ethers.ZeroAddress)
      ).to.be.revertedWith("Zero address");
    });
  });

  describe("Fee and Limit Exclusions", function () {
    it("Should prevent changing fee exclusions after trading enabled", async function () {
      await token.enableTrading();
      
      await expect(
        token.setExcludedFromFees(user1.address, true)
      ).to.be.revertedWith("Cannot change fee-exempt after launch");
    });

    it("Should prevent changing limit exclusions after trading enabled", async function () {
      await token.enableTrading();
      
      await expect(
        token.setExcludedFromLimits(user1.address, true)
      ).to.be.revertedWith("Cannot change limits-exempt after launch");
    });

    it("Should allow changing exclusions before trading enabled", async function () {
      const MockRouter2 = await ethers.getContractFactory("MockRouter");
      const router2 = await MockRouter2.deploy();
      const Kindora2 = await ethers.getContractFactory("Kindora");
      const token2 = await Kindora2.deploy(await router2.getAddress());
      
      await token2.setExcludedFromFees(user1.address, true);
      await token2.setExcludedFromLimits(user1.address, true);
      
      expect(await token2.isExcludedFromFees(user1.address)).to.be.true;
      expect(await token2.isExcludedFromLimits(user1.address)).to.be.true;
    });
  });

  describe("Swap and Limits Toggles", function () {
    beforeEach(async function () {
      await token.enableTrading();
    });

    it("Should toggle swap enabled", async function () {
      await expect(token.setSwapEnabled(false))
        .to.emit(token, "SwapEnabledSet")
        .withArgs(false);
      
      expect(await token.swapEnabled()).to.be.false;
      
      await token.setSwapEnabled(true);
      expect(await token.swapEnabled()).to.be.true;
    });

    it("Should toggle cooldown enabled", async function () {
      await expect(token.setCooldownEnabled(false))
        .to.emit(token, "CooldownEnabledSet")
        .withArgs(false);
      
      expect(await token.cooldownEnabled()).to.be.false;
      
      await token.setCooldownEnabled(true);
      expect(await token.cooldownEnabled()).to.be.true;
    });

    it("Should toggle limits in effect", async function () {
      await expect(token.setLimitsInEffect(false))
        .to.emit(token, "LimitsInEffectSet")
        .withArgs(false);
      
      expect(await token.limitsInEffect()).to.be.false;
      
      await token.setLimitsInEffect(true);
      expect(await token.limitsInEffect()).to.be.true;
    });
  });

  describe("Rescue Tokens", function () {
    it("Should prevent rescuing KNR tokens", async function () {
      await expect(
        token.rescueTokens(await token.getAddress(), 1000)
      ).to.be.revertedWith("Cannot rescue KNR");
    });

    it("Should prevent rescuing LP tokens", async function () {
      await expect(
        token.rescueTokens(pair, 1000)
      ).to.be.revertedWith("Cannot rescue LP");
    });

    it("Should prevent rescuing from zero address", async function () {
      await expect(
        token.rescueTokens(ethers.ZeroAddress, 1000)
      ).to.be.revertedWith("Zero token");
    });
  });

  describe("Edge Cases and Constants", function () {
    it("Should have correct swap threshold", async function () {
      expect(await token.swapThreshold()).to.equal(SWAP_THRESHOLD);
    });

    it("Should have correct tax constants", async function () {
      expect(await token.TAX_TOTAL()).to.equal(5);
      expect(await token.TAX_CHARITY()).to.equal(3);
      expect(await token.TAX_LIQUIDITY()).to.equal(1);
      expect(await token.TAX_BURN()).to.equal(1);
    });

    it("Should have correct initial limits", async function () {
      expect(await token.maxTxAmount()).to.equal(MAX_TX);
      expect(await token.maxWalletAmount()).to.equal(MAX_WALLET);
    });

    it("Should have correct cooldown constant", async function () {
      expect(await token.BUY_COOLDOWN_SECONDS()).to.equal(BUY_COOLDOWN_SECONDS);
    });

    it("Should handle receive function for BNB", async function () {
      const sendAmount = ethers.parseEther("1");
      await expect(
        owner.sendTransaction({
          to: await token.getAddress(),
          value: sendAmount
        })
      ).to.not.be.reverted;
    });
  });

  describe("Event Emissions", function () {
    it("Should emit TradingEnabled event", async function () {
      const MockRouter2 = await ethers.getContractFactory("MockRouter");
      const router2 = await MockRouter2.deploy();
      const Kindora2 = await ethers.getContractFactory("Kindora");
      const token2 = await Kindora2.deploy(await router2.getAddress());
      
      await token2.setCharityWallet(charityWallet.address);
      
      await expect(token2.enableTrading())
        .to.emit(token2, "TradingEnabled");
    });

    it("Should emit Transfer event", async function () {
      await token.enableTrading();
      const amount = ethers.parseEther("1000");
      
      await expect(token.transfer(user1.address, amount))
        .to.emit(token, "Transfer")
        .withArgs(owner.address, user1.address, amount);
    });

    it("Should emit Approval event", async function () {
      const amount = ethers.parseEther("1000");
      
      await expect(token.approve(user1.address, amount))
        .to.emit(token, "Approval")
        .withArgs(owner.address, user1.address, amount);
    });

    it("Should emit MaxTxUpdated event", async function () {
      await token.enableTrading();
      const newMaxTx = MAX_TX + 1n;
      
      await expect(token.setMaxTxAmount(newMaxTx))
        .to.emit(token, "MaxTxUpdated")
        .withArgs(newMaxTx);
    });

    it("Should emit MaxWalletUpdated event", async function () {
      await token.enableTrading();
      const newMaxWallet = MAX_WALLET + 1n;
      
      await expect(token.setMaxWalletAmount(newMaxWallet))
        .to.emit(token, "MaxWalletUpdated")
        .withArgs(newMaxWallet);
    });
  });

  describe("Integration Tests", function () {
    it("Should handle complete buy-sell flow with taxes", async function () {
      await token.enableTrading();
      await router.setSwapBNBMultiplier(ethers.parseUnits("1", 9));
      
      // Setup liquidity
      await token.transfer(pair, ethers.parseEther("100000"));
      
      // Fund pair with ETH for gas when impersonated
      await setBalance(pair, ethers.parseEther("100"));
      
      // Buy
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      const buyAmount = ethers.parseEther("10000");
      const pairSigner = await ethers.getImpersonatedSigner(pair);
      await token.connect(pairSigner).transfer(user1.address, buyAmount);
      
      const userBalance = await token.balanceOf(user1.address);
      expect(userBalance).to.equal(buyAmount * 95n / 100n);
      
      // Sell
      await token.connect(user1).transfer(pair, userBalance / 2n);
      
      // Verify sell happened
      expect(await token.balanceOf(user1.address)).to.be.lt(userBalance);
    });

    it("Should handle multiple users trading", async function () {
      await token.enableTrading();
      await token.transfer(pair, ethers.parseEther("1000000"));
      
      // Fund pair with ETH for gas when impersonated
      await setBalance(pair, ethers.parseEther("100"));
      
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      const pairSigner = await ethers.getImpersonatedSigner(pair);
      
      // User1 buys
      await token.connect(pairSigner).transfer(user1.address, ethers.parseEther("1000"));
      
      await time.increase(BUY_COOLDOWN_SECONDS + 1);
      
      // User2 buys
      await token.connect(pairSigner).transfer(user2.address, ethers.parseEther("2000"));
      
      expect(await token.balanceOf(user1.address)).to.be.gt(0);
      expect(await token.balanceOf(user2.address)).to.be.gt(0);
    });
  });
});
