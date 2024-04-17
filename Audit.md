# Docs for SYNTHR STAKING Contracts 

### Vote Escrow Contract 

Users deposit Uno tokens in this contract and get voting power on the basis of deposit amount and lock period.
https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy

#### Changes in Vote Escrow Contract
* Add createLockTs mapping to store user create lock timestamp

### DerivedDexLpFarming

This contract gives out a constant number of reward tokens per block. User deposits ERC721 tokens in this contract and this contract will update user rewardDebt and amount of liquidity. Master chef logic is used to distribute reward
https://github.com/1coinswap/core/blob/master/contracts/MiniChefV2.sol

#### Changes in DerivedDexLpFarming
- There is only one pool unlike masterchef there is multiple pool functionality, owner can add more pools, but in Farming only one pool is used
- In user Info liquidityX is added to store liquidity user in traderJoy, this liquidity is staked in traderJoy to get token id
- isTokenDeposit function added to fetch if user has deposited token or not
- add _getLiquidity function to fetch liquidity of token id
- Instead of ERC20 token for staking, ERC721 token is used
- Total supply is native token balance of liquidity pool
- Token tracker is ERC721 contract from which user gets token
- Liquidity of token id is fetch from token tracker contract by calling positions function, in master chef user amount updated based on amount of ERC20 token staked by user but in farming it is fetched from token tracker
- added internal functions to reduce redundancy
    - _withdrawAndHarvest
    - _withdraw
    - _deposit
    - _depositLiquidity
    - _withdrawLiquidity
    - _calAccumulatedReward
    - _calAccPerShare


### Synthr Staking

This contract gives out a constant number of reward tokens per block. User deposits ERC20 Synthr tokens in this contract and this contract will update user rewardDebt and amount of liquidity. Master chef logic is used to distribute reward
https://github.com/1coinswap/core/blob/master/contracts/MiniChefV2.sol

#### Changes in Synthr Staking

- Different pools is different lock type which is unlock time in seconds(Eg. 6, 9, 12, 18 months in seconds)

##### each lock type have:
- maxPoolSize: maximum staking allow in this lock type
- Penalty: user staked amount will be deducted by this percentage if withdraw before unlock time ends
- totalStaked: return total staked in this lock type
- Exist: return bool to show this lock type is exist or not
- coolDownPeriod: user have to wait for this period after withdrawRequest to withdraw actual tokens
- In user info lockType and unlockEnd is added, to return user staked in which lockType and unlockEnd returns after which user can withdraw its token without penalty
- Add kill and pause functionality
    - In pause, all functionality will be deprecated, updateEpoch, deposit, claim, withdraw and emergencyWithdraw
    - In kill, only withdraw and claim functionality is allowed
- User can not deposit in different lock type at the same time
- User can not deposit if lock time ends, need to withdraw first then deposit again
- User can claim after unlock time ends
- In synthStaking like master chef there is no only withdraw function, in this withdraw function will return user staked token with pending reward generated till time and and user can only withdraw all tokens unlike master chef where user can withdraw all or some amount of tokens from pool
- Cool down feature is added, user need to request first for withdraw, this will update cool down period of user based on lock type and then user can withdraw after cool down ends
- Penalty is there if user withdraw before unlock time ends
- added internal functions to reduce redundancy
    - _calAccPerShare
    - _calAccRewardPerShare
    - _calAccumaltedAndPendingReward


### NFT Staking

This contract gives out a constant number of reward tokens per block. User deposits ERC20 Synthr tokens in this contract and this contract will update user rewardDebt and amount of liquidity. Master chef logic is used to distribute reward
https://github.com/1coinswap/core/blob/master/contracts/MiniChefV2.sol

#### Changes in NFT

- SynthNFT contracts are different pools in NFT staking
- each NFT pool has:
    - lastRewardBlock: last block number when pool updated
    - accRewardPerShare: accumulated reward generated per share till last updated time
    - rewardPerBlock: reward per block to distribute to user
    - Exist: return bool to show this lock type is exist or not
    - Epoch: current epoch
- In user Info tokenId is added, to track owner of tokenId who staked in this contract
- Reward token is SYNTH token
- users can stake their non-fungible tokens (NFTs) into a pool from which they were originally minted
- User can stake NFT when it has more than 1000 token staked in SynthrStaking and its unlock time should be greater than current time
- totalLockAmount, set by owner, it is total amount of token staked by NFT users in SynthrStaking
- secondPerBlock, number of seconds takes new block is confirmed after exexuting transaction
- There is excess reward for user whose lock time ends, to remove this internal function is made to calculate excess reward which is reward between unlock time of user fetch from synthStaking and current time, this excess reward will be deducting from pending reward generated of user
    - to deduct difference of unlock time and current time is converted to difference of block number by dividing it with secondPerBlock
    - There is an assumption that each block takes 12 sec to confirm
- At the time of withdraw user token id passed to user and it reward accumulation stop
- Added increase deposit function separately to add update lock amount to sync with SynthrStaking, if user staked more tokens in SynthStaking, then user will call this function to update this on NFTStaking
- User amount update in master chef based on amount of token user user staking but in NFTStaking it is fetch from SynthStaking
- added internal functions to reduce redundancy
    - _calAccPerShare
    - _calAccRewardPerShare
    - _calAccumaltedAndPendingReward



### Latest deployed contracts

- SynthToken: 
- SynthrStaking: 
- NftStaking: 

#### NFT pools: 
- SyCHAD: 
- SyMAXI: 
- SyDIAMOND: 
- SyBULL:


## Contracts in scope (commit: )

| Type | File   | Logic Contracts | Interfaces | Lines | nLines | nSLOC | Comment Lines | Complex. Score | Capabilities |
| ---- | ------ | --------------- | ---------- | ----- | ------ | ----- | ------------- | -------------- | ------------ | 
| 📝 | ./VotingEscrow.sol | 1 | 1 | 563 | ? | ? | ? | 
| 📝 | ./controller/GuageContoller.sol | 1 | **** | 367 | ? | ? | ? | ? | **** |
| 📝 | ./apps/VeYieldDistributor.sol | 1 | 2 | 333 | ? | ? | ? | ? | **** |
| 📚 | ./farming/BaseDexLpFarming.sol | 1 | **** | 195 | ? | ? | ? | ? | **** |
| 📝 | ./farming/DerivedDexLpFarming.sol | 1 | 1 | 173 | ? | ? | ? | ? | **** |
| 📝 | ./NFT-Staking/SynthNFT.sol | 1 | **** | 56 | ? | 10 | ? | 9 | **** |
| 📝 | ./NFT-Staking/NftStaking.sol | 1 | 2 | 440 | ? | ? | ? | 9 | **** |
| 📝 | ./SynthrStaking.sol | 1 | **** | 384 | ? | ? | ? | ? | **** |
| 📝 | ./Voter.sol | 1 | 2 | 256 | ? | ? | ? | ? | **** |
| 📝📚🔍 | **Totals** | **?** | **?** | **?**  | **?** | **?** | **?** | **?** | **<abbr title='Uses Assembly'>🖥</abbr><abbr title='Payable Functions'>💰</abbr><abbr title='Initiates ETH Value Transfer'>📤</abbr><abbr title='DelegateCall'>👥</abbr><abbr title='Uses Hash-Functions'>🧮</abbr><abbr title='Handles Signatures: ecrecover'>🔖</abbr><abbr title='Unchecked Blocks'>Σ</abbr>** |


## Contracts not in scope for audit (commit: )

| Type | File   | Logic Contracts | Interfaces | Lines | nLines | nSLOC | Comment Lines | Complex. Score | Capabilities |
| ---- | ------ | --------------- | ---------- | ----- | ------ | ----- | ------------- | -------------- | ------------ | 
| 📝 | **Totals** | **?** | **?** | **?**  | **?** | **?** | **?** | **?** | **<abbr title='Uses Assembly'>🖥</abbr><abbr title='Payable Functions'>💰</abbr><abbr title='Initiates ETH Value Transfer'>📤</abbr><abbr title='DelegateCall'>👥</abbr><abbr title='Uses Hash-Functions'>🧮</abbr><abbr title='Handles Signatures: ecrecover'>🔖</abbr><abbr title='Unchecked Blocks'>Σ</abbr>** |


### Special Attention to code
- excess reward calculation in NftStaking contract(_pendingRewardDeduction) 
    - excess reward is reward generated after end of unlock time in SynthStaking 
    - this function used to deduct excess reward from pending reward generated for user
- secondPerBlock in NftStaking: this is approximately time required to confirm block after execution of transaction
    - used to convert time difference into block difference betweeen unlock time and curent time


### Cli Commands

#### deploy commands

- npx hardhat deploy --network {NETWORK}
- DexLpFarming: npx hardhat run --network {NETWORK} scripts/DexLPFarming.deploy.ts
- GaugeController: npx hardhat run --network {NETWORK} scripts/GaugeController.deploy.ts
 
### Openzeppelin contracts used

- SafeERC20
- AccessControl
- Ownable2Step, Ownable
- ReentrancyGuard
- IERC721Receiver
- Pausable
- ERC20Burnable

### Others contracts  

- TransferHelper
- Math
- Time


These are already audited smart contracts and we are keeping it out of scope of current audit.

VotingEscrow
- Repository: https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy 
- Audit report: https://github.com/mixbytes/audits_public/blob/master/Curve%20Finance/DAO%20Voting/Curve%20Finance%20DAO%20Voting%20Security%20Audit%20Report.pdf 

MasterChefV2
- repository: https://github.com/1coinswap/core/blob/master/contracts/MiniChefV2.sol

