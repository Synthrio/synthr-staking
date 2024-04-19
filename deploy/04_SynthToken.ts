import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { parseUnits } from "ethers/lib/utils";


const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer } = await getNamedAccounts();
    let owner = deployer;

    let totalSupply = parseUnits("100000000000000000000", 18);

    await deploy('Synthr', {
        from: deployer,
        contract: 'Synthr',
        args: [owner, owner, totalSupply],
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    });
};
export default func;
func.tags = ['Synthr'];
