import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import { notDeepEqual } from "assert";
import exp from "constants";
import { read } from "fs";
import { ALL } from "dns";

interface RewardInfo {
  token: string;
  rewardPerBlock: BigNumber;
  accRewardPerShare: number;
}

let owner: any,
  addr1: any,
  addr2: any,
  Alice: any,
  Bob: any,
  Joy: any,
  Roy: any,
  Matt: any;
let nftStaking: any, rewardToken: any;

let syCHAD: any, syBULL: any, syHODL: any, syDIAMOND: any, syMAXI: any;
let pools: any;
let totalLockAmount: any;
let yieldDis:any;

let gaugeController: any, votingEscrow: any, lpTtoken: any;
async function setUp() {
  // Contracts are deployed using the first signer/account by default
  [owner, addr1, addr2, Alice, Bob, Joy, Roy, Matt] = await ethers.getSigners();
  const RewardToken = await ethers.getContractFactory("MockToken");
  rewardToken = await RewardToken.deploy();

  const LpTtoken = await ethers.getContractFactory("MockToken");
  lpTtoken = await LpTtoken.deploy();

  await lpTtoken.mint(addr1.address, parseUnits("100000", 18));

  await rewardToken.mint(
    addr2.address,
    parseUnits("10000000000000000000000", 18)
  );

  await rewardToken.mint(
    owner.address,
    parseUnits("10000000000000000000000", 18)
  );

  
  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  votingEscrow = await VotingEscrow.deploy(
      lpTtoken.address,
      "vot",
      "vt",
      "v.0.1"
    );
    
    const YieldDis = await ethers.getContractFactory("VeYieldDistributor");
    yieldDis = await YieldDis.deploy(owner.address, rewardToken.address, owner.address, votingEscrow.address);

    await yieldDis.setYieldRate(BigNumber.from(1).mul(BigNumber.from(10).pow(17)), false);
    
    // await yieldDis.setYieldDuration(60*60);
    await rewardToken.mint(owner.address, parseUnits("10000000000000000000000", 18));
    await rewardToken.approve(
        yieldDis.address,
      parseUnits("10000000000000000000000", 18)
    );
    await yieldDis.notifyRewardAmount(parseUnits("100000000000", 18));

}


async function createLockTx(user:any) {
  await lpTtoken.mint(
    user.address,
    parseUnits("100000000000000000000000", 18)
  );

  await lpTtoken
    .connect(user)
    .approve(votingEscrow.address, parseUnits("10000", 18));
  const blockNum = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blockNum);
  const timestamp = block.timestamp;
  await votingEscrow
    .connect(user)
    .createLock(parseUnits("10000", 18), timestamp + 86400 * 365);
}



describe("Yield distributor", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.

  beforeEach(async () => {
    await setUp();
  });

  describe("Funtions", function () {
    it("Should not yield reward after withdraw", async function () {
      await createLockTx(Alice);
      await createLockTx(Roy);

      await yieldDis.connect(Alice).checkpoint();

      await mine(10);
      let latesTime = await time.latest();
      await time.increaseTo(latesTime + 10);

      let befBalance = await rewardToken.balanceOf(Alice.address);

    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    const timestamp = block.timestamp;

      let earn = await yieldDis.earned(Alice.address);
      console.log(await votingEscrow.totalSupplyAtTime(timestamp + 3));
      console.log(earn);
      await yieldDis.connect(Alice).getYield();

      expect(await rewardToken.balanceOf(Alice.address)).to.equal(befBalance.add(earn));

      await mine(86400 * 365);

      let befBalance1 = await rewardToken.balanceOf(Alice.address);
      await votingEscrow.connect(Alice).withdraw();
      
      await mine(100000000000);
      await yieldDis.notifyRewardAmount(parseUnits("1000000000", 18));

      await yieldDis.connect(Alice).getYield();

      expect(await rewardToken.balanceOf(Alice.address)).to.equal(befBalance1);

    });

    it("Should update user balance after creat lock", async function () {
        await createLockTx(Alice);
        const blockNum = await ethers.provider.getBlockNumber();
        const block = await ethers.provider.getBlock(blockNum);
        const timestamp = block.timestamp;
        let balanceOfAlice = await votingEscrow.balanceOfAtTime(Alice.address, timestamp + 1);
        await yieldDis.connect(Alice).checkpoint();
        expect(await yieldDis.userVeCheckpointed(Alice.address)).to.equal(balanceOfAlice);
  
      });

    it("Should update zero balance of user in distributor without creat lock ", async function () {
        const blockNum = await ethers.provider.getBlockNumber();
        await yieldDis.connect(Alice).checkpoint();
        console.log((await yieldDis.userVeCheckpointed(Alice.address)));  
    });

    it("Should earned zero reward without creat lock in voting esrow", async function () {
        await yieldDis.connect(Alice).checkpoint();
        
        await mine(100);

        expect(await yieldDis.earned(Alice.address)).to.equal(0)
    });

    it("Should earned zero reward without if reward did not notify reward", async function () {
        await yieldDis.connect(Alice).checkpoint();
        
        await mine(100);

        expect(await yieldDis.earned(Alice.address)).to.equal(0)
    });
  });
});
