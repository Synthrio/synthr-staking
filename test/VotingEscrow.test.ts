import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

interface RewardInfo {
  token: string;
  rewardPerBlock: BigNumber;
  accRewardPerShare: number;
}

let owner: any, addr1: any, addr2: any, Alice: any, Bob: any, Joy: any;
let gaugeController: any,
  votingEscrow: any,
  lpTtoken: any,
  rewardToken: any,
  rewardToken1: any;
async function setUp() {
  // Contracts are deployed using the first signer/account by default
  [owner, addr1, addr2, Alice, Bob, Joy] = await ethers.getSigners();

  const GaugeController = await ethers.getContractFactory("GaugeController");
  gaugeController = await GaugeController.deploy(owner.address);

  const LpToken = await ethers.getContractFactory("MockToken");
  lpTtoken = await LpToken.deploy();

  const RewardToken = await ethers.getContractFactory("MockToken");
  rewardToken = await RewardToken.deploy();
  const RewardToken1 = await ethers.getContractFactory("MockToken");
  rewardToken1 = await RewardToken1.deploy();
  await lpTtoken.mint(addr1.address, parseUnits("100000", 18));
  await lpTtoken.mint(addr2.address, parseUnits("100000", 18));
  await lpTtoken.mint(Alice.address, parseUnits("100000", 18));
  await lpTtoken.mint(Bob.address, parseUnits("100000", 18));
  await lpTtoken.mint(Joy.address, parseUnits("100000", 18));

  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  votingEscrow = await VotingEscrow.deploy(
    lpTtoken.address,
    gaugeController.address,
    "vot",
    "vt",
    "v.0.1"
  );
}

async function addPoolFunc() {
  const epoch = 0;

  let reward: RewardInfo[] = [
    {
      token: rewardToken.address,
      rewardPerBlock: parseUnits("1000", 18),
      accRewardPerShare: 0,
    },
  ];

  let tx = await gaugeController.addPool(
    lpTtoken.address,
    votingEscrow.address,
    reward
  );
  return tx;
}

async function createLock(_value: BigNumber, _unlockTime: BigNumber, signer: any) {
  let txn = await votingEscrow
    .connect(signer)
    .createLock(_value, _unlockTime);
  return txn;
}

describe("VotingEscrow", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.

  beforeEach(async () => {
    await setUp();
  });

  describe("Funtions", function () {
    it("Should create lock", async function () {
      await addPoolFunc();

      await lpTtoken
        .connect(addr1)
        .approve(votingEscrow.address, parseUnits("1000", 18));

      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      let time1 = timestamp + 1000000;
      expect(
        await votingEscrow
          .connect(addr1)
          .createLock(parseUnits("1000", 18), time1)
      );
      let userLockedInfo = await votingEscrow.locked(addr1.address);
      let calUnlockTime = BigNumber.from(time1)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));

      expect(userLockedInfo.end).to.equal(calUnlockTime);
      expect(userLockedInfo.amount).to.equal(parseUnits("1000", 18));
      expect(
        await gaugeController.userInfo(votingEscrow.address, addr1.address)
      ).to.equal(parseUnits("1000", 18));
    });

    it("Should create lock & increase lock amount", async function () {
      await addPoolFunc();

      await lpTtoken
        .connect(Alice)
        .approve(votingEscrow.address, parseUnits("1000", 18));

      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      let unlockTime = BigNumber.from(timestamp + 1000000);
      let _value = parseUnits("1000", 18);

      let createLockTxn = await createLock(_value, unlockTime, Alice)
      let createLockTS = (await ethers.provider.getBlock(createLockTxn.blockNumber)).timestamp;


      let calUnlockTime = BigNumber.from(unlockTime)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));
      let userLockedInfo = await votingEscrow.locked(Alice.address);

      expect(createLockTxn).to.emit(votingEscrow, "Deposited").withArgs(Alice.address, _value, calUnlockTime, 1, createLockTS)

      expect(userLockedInfo.end).to.equal(calUnlockTime);
      expect(userLockedInfo.amount).to.equal(_value);
      expect(
        await gaugeController.userInfo(votingEscrow.address, Alice.address)
      ).to.equal(_value);

      await lpTtoken
        .connect(Alice)
        .approve(votingEscrow.address, parseUnits("100", 18));
      let _value2 = parseUnits("100", 18);

      let tx = await votingEscrow.connect(Alice).increaseAmount(_value2);
      let increaseAmountTS = (await ethers.provider.getBlock(tx.blockNumber)).timestamp;

      expect(tx).to.emit(votingEscrow, "Deposited").withArgs(Alice.address, _value2, calUnlockTime, 2, increaseAmountTS)

    });

    it("Should create lock & increase lock time", async function () {
      await addPoolFunc();

      await lpTtoken
        .connect(Alice)
        .approve(votingEscrow.address, parseUnits("1000", 18));

      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      let unlockTime = BigNumber.from(timestamp + 1000000);
      let _value = parseUnits("1000", 18);

      let createLockTxn = await createLock(_value, unlockTime, Alice)
      let createLockTS = (await ethers.provider.getBlock(createLockTxn.blockNumber)).timestamp;


      let calUnlockTime = BigNumber.from(unlockTime)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));
      let userLockedInfo = await votingEscrow.locked(Alice.address);

      expect(createLockTxn).to.emit(votingEscrow, "Deposited").withArgs(Alice.address, _value, calUnlockTime, 1, createLockTS)

      expect(userLockedInfo.end).to.equal(calUnlockTime);
      expect(userLockedInfo.amount).to.equal(_value);
      expect(
        await gaugeController.userInfo(votingEscrow.address, Alice.address)
      ).to.equal(_value);

      let newUnlockTime = unlockTime.add(BigNumber.from(1000000));
      let calUnlockTime2 = BigNumber.from(newUnlockTime)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));
      let tx = await votingEscrow.connect(Alice).increaseUnlockTime(newUnlockTime);
      let increaseUnlockTimeTS = (await ethers.provider.getBlock(tx.blockNumber)).timestamp;

      expect(tx).to.emit(votingEscrow, "Deposited").withArgs(Alice.address, 0, calUnlockTime2, 3, increaseUnlockTimeTS)

    });

    it("Should create lock & withdraw lp tokens", async function () {
      await addPoolFunc();

      await lpTtoken
        .connect(Alice)
        .approve(votingEscrow.address, parseUnits("1000", 18));
      let balanceBeforeLock = await lpTtoken.balanceOf(Alice.address);
      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      let unlockTime = BigNumber.from(timestamp + 1000000);
      let _value = parseUnits("1000", 18);

      let createLockTxn = await createLock(_value, unlockTime, Alice)
      let createLockTS = (await ethers.provider.getBlock(createLockTxn.blockNumber)).timestamp;


      let calUnlockTime = BigNumber.from(unlockTime)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));
      let userLockedInfo = await votingEscrow.locked(Alice.address);

      expect(createLockTxn).to.emit(votingEscrow, "Deposited").withArgs(Alice.address, _value, calUnlockTime, 1, createLockTS)

      expect(userLockedInfo.end).to.equal(calUnlockTime);
      expect(userLockedInfo.amount).to.equal(_value);
      expect(
        await gaugeController.userInfo(votingEscrow.address, Alice.address)
      ).to.equal(_value);
      mine(1000000); // mining 1000000 blocks after deposit so that to pass lock time
      let withdrawTxn = await votingEscrow.connect(Alice).withdraw();
      let withdrawTS = (await ethers.provider.getBlock(withdrawTxn.blockNumber)).timestamp;
      let balanceAfterWithdraw = await lpTtoken.balanceOf(Alice.address);

      expect(withdrawTxn).to.emit(votingEscrow, "Withdrew").withArgs(Alice.address, _value, withdrawTS);
      expect(balanceBeforeLock).to.equal(balanceAfterWithdraw);

    });

    it("Should revert if create lock & increase lock time with different account", async function () {
      await addPoolFunc();

      await lpTtoken
        .connect(Alice)
        .approve(votingEscrow.address, parseUnits("1000", 18));

      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      let unlockTime = BigNumber.from(timestamp + 1000000);
      let _value = parseUnits("1000", 18);

      let createLockTxn = await createLock(_value, unlockTime, Alice)
      let createLockTS = (await ethers.provider.getBlock(createLockTxn.blockNumber)).timestamp;


      let calUnlockTime = BigNumber.from(unlockTime)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));
      let userLockedInfo = await votingEscrow.locked(Alice.address);

      expect(createLockTxn).to.emit(votingEscrow, "Deposited").withArgs(Alice.address, _value, calUnlockTime, 1, createLockTS)

      expect(userLockedInfo.end).to.equal(calUnlockTime);
      expect(userLockedInfo.amount).to.equal(_value);
      expect(
        await gaugeController.userInfo(votingEscrow.address, Alice.address)
      ).to.equal(_value);
      let newUnlockTime = unlockTime.add(BigNumber.from(1000000));
      let calUnlockTime2 = BigNumber.from(newUnlockTime)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));
      await expect(votingEscrow.connect(Bob).increaseUnlockTime(newUnlockTime)).to.revertedWith("VotingEscrow: Lock expired");


    });

    it("Should revert if create lock & increase lock amount with other account", async function () {
      await addPoolFunc();

      await lpTtoken
        .connect(Alice)
        .approve(votingEscrow.address, parseUnits("1000", 18));

      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      let unlockTime = BigNumber.from(timestamp + 1000000);
      let _value = parseUnits("1000", 18);

      let createLockTxn = await createLock(_value, unlockTime, Alice)
      let createLockTS = (await ethers.provider.getBlock(createLockTxn.blockNumber)).timestamp;


      let calUnlockTime = BigNumber.from(unlockTime)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));
      let userLockedInfo = await votingEscrow.locked(Alice.address);

      expect(createLockTxn).to.emit(votingEscrow, "Deposited").withArgs(Alice.address, _value, calUnlockTime, 1, createLockTS)

      expect(userLockedInfo.end).to.equal(calUnlockTime);
      expect(userLockedInfo.amount).to.equal(_value);
      expect(
        await gaugeController.userInfo(votingEscrow.address, Alice.address)
      ).to.equal(_value);

      await lpTtoken
        .connect(Bob)
        .approve(votingEscrow.address, parseUnits("100", 18));
      let _value2 = parseUnits("100", 18);

      await expect(votingEscrow.connect(Bob).increaseAmount(_value2)).to.revertedWith("VotingEscrow: No existing lock found");

    });

    it("Should increase lock amount and unlock time", async function () {
      await addPoolFunc();

      await lpTtoken
        .connect(addr1)
        .approve(votingEscrow.address, parseUnits("2000", 18));

      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      let time1 = timestamp + 1000000;
      expect(
        await votingEscrow
          .connect(addr1)
          .createLock(parseUnits("1000", 18), time1)
      );

      let calUnlockTime = BigNumber.from(time1)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));

      expect(await votingEscrow.lockedEnd(addr1.address)).to.equal(
        calUnlockTime
      );

      expect(
        await gaugeController.userInfo(votingEscrow.address, addr1.address)
      ).to.equal(parseUnits("1000", 18));
      await votingEscrow
        .connect(addr1)
        .increaseAmountAndUnlockTime(parseUnits("1000", 18), time1 + 1000000);

      let calUnlockTime1 = BigNumber.from(time1)
        .add(1000000)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));
      let userLockedInfo = await votingEscrow.locked(addr1.address);

      expect(userLockedInfo.end).to.equal(calUnlockTime1);
      expect(userLockedInfo.amount).to.equal(parseUnits("2000", 18));
      expect(
        await gaugeController.userInfo(votingEscrow.address, addr1.address)
      ).to.equal(parseUnits("2000", 18));
    });


  });
});
