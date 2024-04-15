import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { parseUnits } from "ethers/lib/utils";


const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer } = await getNamedAccounts();
    let owner = deployer;

    let rewardToken = process.env.REWARD_TOKEN_ARBITRUM_SEPOLIA_ADDRESS;

    let lockValue: any = [{
        maxPoolSize: parseUnits("2000000", 18),
        penalty: 40,
        coolDownPeriod: 60*60*24*15,
        totalStaked: 0,
        exist: true,
        lastRewardBlock: 0,
        rewardPerBlock:parseUnits("33333", 18),
        accRewardPerShare: 0,
        epoch: 1,
    }, {
        maxPoolSize: parseUnits("3000000", 18),
        penalty: 35,
        coolDownPeriod: 60*60*24*12,
        totalStaked: 0,
        exist: true,
        lastRewardBlock: 0,
        rewardPerBlock:parseUnits("112500", 18),
        accRewardPerShare: 0,
        epoch: 1,
    }, {maxPoolSize: parseUnits("4000000", 18),
        penalty: 30,
        coolDownPeriod: 60*60*24*9,
        totalStaked: 0,
        exist: true,
        lastRewardBlock: 0,
        rewardPerBlock:parseUnits("666667", 18),
        accRewardPerShare: 0,
        epoch: 1,
    }, {maxPoolSize: parseUnits("5000000", 18),
        penalty: 25,
        coolDownPeriod: 60*60*24*6,
        totalStaked: 0,
        exist: true,
        lastRewardBlock: 0,
        rewardPerBlock:parseUnits("1250000", 18),
        accRewardPerShare: 0,
        epoch: 1,
    }];

    let lockAmount = [60*60*24*30*6, 60*60*24*30*9, 60*60*24*30*12, 60*60*24*30*18];

    await deploy('SynthrStaking', {
        from: deployer,
        contract: 'SynthrStaking',
        args: [owner, rewardToken, lockAmount, lockValue],
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    });
};
export default func;
func.tags = ['SynthrStaking'];
