import { BigNumber, Wallet } from 'ethers'
import { ethers } from 'hardhat'
import { TestToken } from '../../typechain/TestToken'
import { GameTicket } from '../../typechain/GameTicket'
import { GameTicket2 } from '../../typechain/GameTicket2'
import { GameConfig } from '../../typechain/GameConfig'
import { GamePool } from '../../typechain/GamePool'
import { GamePoolActivity } from '../../typechain/GamePoolActivity'
import { GamePoolCS } from '../../typechain/GamePoolCS'
import { GameToken } from '../../typechain/GameToken'
import { GameSchedualPool } from '../../typechain/GameSchedualPool'
import { GameAirdrop } from '../../typechain/GameAirdrop'
import { GameTimeLock } from '../../typechain/GameTimeLock'
import { Fixture } from 'ethereum-waffle'

export const bigNumber18 = BigNumber.from("1000000000000000000")  // 1e18
export const bigNumber17 = BigNumber.from("100000000000000000")  //1e17
export const dateNow = BigNumber.from("1636429275") // 2021-11-09 11:41:15

export async function getBlockNumber() {
    const blockNumber = await ethers.provider.getBlockNumber()
    console.debug("Current block number: " + blockNumber);
    return blockNumber;
}

interface TestTokensFixture {
    buyToken: TestToken
}

async function testTokensFixture(): Promise<TestTokensFixture> {
    let testTokenFactory = await ethers.getContractFactory('TestToken')
    let buyToken = (await testTokenFactory.deploy()) as TestToken
    await buyToken.initialize();
    return { buyToken }
}


interface GameTicketFixture extends TestTokensFixture {
    gameTicket: GameTicket
    gameConfig: GameConfig
}

export const gameTicketFixture: Fixture<GameTicketFixture> = async function (): Promise<GameTicketFixture> {
    return await _gameTicketFixture();
}

async function _gameTicketFixture(): Promise<GameTicketFixture> {
    const { buyToken } = await testTokensFixture();

    const gameConfigFactory = await ethers.getContractFactory('GameConfig');
    const gameTicketFactory = await ethers.getContractFactory('GameTicket');

    const gameConfig = (await gameConfigFactory.deploy()) as GameConfig;
    await gameConfig.initialize();

    const gameTicket = (await gameTicketFactory.deploy()) as GameTicket;
    await gameTicket.initialize(buyToken.address, bigNumber18);
    await gameTicket.setupConfig(gameConfig.address);

    return { buyToken, gameTicket, gameConfig };
}


interface GamePoolFixture extends GameTicketFixture {
    gameToken: GameToken
    gamePoolDay: GamePool
    gamePoolWeek: GamePool
    gamePoolMonth: GamePool
}

export const gamePoolFixture: Fixture<GamePoolFixture> = async function (): Promise<GamePoolFixture> {
    const { buyToken, gameTicket, gameConfig } = await _gameTicketFixture();

    const gameTokenFactory = await ethers.getContractFactory('GameToken');
    const gamePoolFactory = await ethers.getContractFactory('GamePool');

    const gameToken = (await gameTokenFactory.deploy()) as GameToken;
    await gameToken.initialize();
    const gamePoolDay = (await gamePoolFactory.deploy()) as GamePool;
    await gamePoolDay.initialize();
    const gamePoolWeek = (await gamePoolFactory.deploy()) as GamePool;
    await gamePoolWeek.initialize()
    const gamePoolMonth = (await gamePoolFactory.deploy()) as GamePool;
    await gamePoolMonth.initialize()

    await gameToken.increaseFunds([gamePoolDay.address, gamePoolWeek.address, gamePoolMonth.address], [ethers.constants.MaxUint256, ethers.constants.MaxUint256, ethers.constants.MaxUint256])
    await gamePoolDay.configure(
        gameTicket.address,
        gameToken.address,
        gamePoolWeek.address,
        2000,
        1,
        1,
        true,
        false
    );
    await gamePoolWeek.configure(
        gamePoolDay.address,
        gameToken.address,
        gamePoolMonth.address,
        2000,
        2,
        2,
        false,
        false
    );
    await gamePoolMonth.configure(
        gamePoolWeek.address,
        gameToken.address,
        ethers.constants.AddressZero,
        0,
        3,
        3,
        false,
        false
    );
    await gameTicket.setRewardPool(gamePoolDay.address);

    return { buyToken, gameTicket, gameConfig, gameToken, gamePoolDay, gamePoolWeek, gamePoolMonth };
}


interface GameSchedualPoolFixture {
    depositToken: TestToken
    rewardToken: GameToken
    pool: GameSchedualPool
}

export const gameSchedualPoolFixture: Fixture<GameSchedualPoolFixture> = async function ([wallet, other]: Wallet[]): Promise<GameSchedualPoolFixture> {
    let testTokenFactory = await ethers.getContractFactory('TestToken')
    let depositToken = (await testTokenFactory.deploy()) as TestToken
    await depositToken.initialize();
    await depositToken.mint(wallet.address, bigNumber18.mul(10000));

    let rewardTokenFactory = await ethers.getContractFactory('GameToken');
    let rewardToken = (await rewardTokenFactory.deploy()) as GameToken;
    await rewardToken.initialize();


    let poolFactory = await ethers.getContractFactory('GameSchedualPool');
    let pool = (await poolFactory.deploy()) as GameSchedualPool
    await pool.initialize(
        depositToken.address,
        rewardToken.address,
        BigNumber.from('1640966400'),
        bigNumber18.mul(10),
        0
    );
    await rewardToken.increaseFund(pool.address, ethers.constants.MaxUint256);

    return { depositToken, rewardToken, pool };
}

interface GameAirdropFixture {
    gameToken: GameToken
    gameAirdrop: GameAirdrop
}

export const gameAirdropFixture: Fixture<GameAirdropFixture> = async function (): Promise<GameAirdropFixture> {
    let gameTokenFactory = await ethers.getContractFactory('GameToken');
    let gameToken = (await gameTokenFactory.deploy()) as GameToken;
    await gameToken.initialize();


    let airdropFactory = await ethers.getContractFactory('GameAirdrop');
    let gameAirdrop = (await airdropFactory.deploy()) as GameAirdrop;


    await gameAirdrop.initialize(
        gameToken.address,
        bigNumber18.mul(100),
        BigNumber.from(dateNow),
        BigNumber.from(dateNow).add(259200) // 3 days
    )

    await gameToken.increaseFund(gameAirdrop.address, bigNumber18.mul(1000));

    return { gameToken, gameAirdrop }
}

interface GamePoolsFixture {
    buyToken: TestToken
    gameToken: GameToken
    gameTicket: GameTicket
    gameTicket2: GameTicket2
    gamePool: GamePool
    gamePoolActivity: GamePoolActivity
    gamePoolCS: GamePoolCS
}

export const gamePoolsFixture: Fixture<GamePoolsFixture> = async function ([wallet, other]: Wallet[]): Promise<GamePoolsFixture> {
    const gameTicketFactory = await ethers.getContractFactory('GameTicket');
    const gameTicket2Factory = await ethers.getContractFactory('GameTicket2');
    const gamePoolFactory = await ethers.getContractFactory('GamePool');
    const gamePoolActivityFactory = await ethers.getContractFactory('GamePoolActivity');
    const gamePoolCSFactory = await ethers.getContractFactory('GamePoolCS');
    const gameTokenFactory = await ethers.getContractFactory('GameToken');
    const testTokenFactory = await ethers.getContractFactory('TestToken')
    const gameConfigFactory = await ethers.getContractFactory('GameConfig');

    const gameConfig = (await gameConfigFactory.deploy()) as GameConfig;
    await gameConfig.initialize();

    let buyToken = (await testTokenFactory.deploy()) as TestToken
    await buyToken.initialize();

    let gameToken = (await gameTokenFactory.deploy()) as GameToken;
    await gameToken.initialize();
    await gameToken.increaseFund(wallet.address, ethers.constants.MaxUint256);

    let gameTicket = (await gameTicketFactory.deploy()) as GameTicket;
    await gameTicket.initialize(buyToken.address, bigNumber18);
    await gameTicket.setupConfig(gameConfig.address);

    let gameTicket2 = (await gameTicket2Factory.deploy()) as GameTicket2;
    await gameTicket2.initialize(buyToken.address, gameToken.address, bigNumber18, bigNumber18.mul(10), bigNumber18.mul(100));
    await gameTicket2.setupConfig(gameConfig.address);


    let gamePool = (await gamePoolFactory.deploy()) as GamePool;
    await gamePool.initialize();
    await gamePool.setupConfig(gameConfig.address);
    let gamePoolActivity = (await gamePoolActivityFactory.deploy()) as GamePoolActivity;
    await gamePoolActivity.initialize();
    await gamePoolActivity.setupConfig(gameConfig.address);
    let gamePoolCS = (await gamePoolCSFactory.deploy()) as GamePoolCS;
    await gamePoolCS.initialize();
    await gamePoolCS.setupConfig(gameConfig.address);

    await gamePool.configure(
        gameTicket.address,
        gameToken.address,
        gamePoolCS.address,
        2000,
        1,
        1,
        true,
        false
    );

    await gamePoolActivity.configure(
        gameTicket2.address,
        gameToken.address,
        gamePoolCS.address,
        1,
        0,
        true,
        false
    );

    await gamePoolCS.configure(
        buyToken.address,
        gameToken.address,
        1,
        0,
        false
    );

    await gameTicket.setRewardPool(gamePool.address);
    await gameTicket2.setRewardPool(gamePoolActivity.address);

    return { buyToken, gameToken, gameTicket, gameTicket2, gamePool, gamePoolActivity, gamePoolCS }
}

interface GameTimeLockFixture {
    lockToken: TestToken
    gameTimeLock: GameTimeLock
}

export const gameTimeLockFixture: Fixture<GameTimeLockFixture> = async function ([wallet]: Wallet[]): Promise<GameTimeLockFixture> {
    let testTokenFactory = await ethers.getContractFactory('TestToken')
    let lockToken = (await testTokenFactory.deploy()) as TestToken
    await lockToken.initialize();

    let gameTimeLockFactory = await ethers.getContractFactory('GameTimeLock')
    let gameTimeLock = (await gameTimeLockFactory.deploy()) as GameTimeLock
    await gameTimeLock.initialize(lockToken.address, BigNumber.from(5))

    await lockToken.mint(wallet.address, bigNumber18.mul(10000));
    return { lockToken, gameTimeLock }
}
