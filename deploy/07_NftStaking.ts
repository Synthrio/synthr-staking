import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';


const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer } = await getNamedAccounts();
    let owner = deployer;

    let ve = (await deployments.get("SynthrStaking")).address;
    console.log(ve);

    let rewardToken = process.env.REWARD_TOKEN_ARBITRUM_SEPOLIA_ADDRESS;

    await deploy('NftStaking', {
        from: deployer,
        contract: 'NftStaking',
        args: [owner, rewardToken, ve],
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    });
};
export default func;
func.tags = ['NftStaking'];
