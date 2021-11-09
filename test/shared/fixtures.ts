import { BigNumber, Wallet } from 'ethers'
import { ethers } from 'hardhat'
import { TestToken } from '../../typechain/TestToken'
import { GameTicket } from '../../typechain/GameTicket'
import { GameConfig } from '../../typechain/GameConfig'
import { GamePool } from '../../typechain/GamePool'
import { GameToken } from '../../typechain/GameToken'
import { GameSchedualPool } from '../../typechain/GameSchedualPool'
import { GameAirdrop } from '../../typechain/GameAirdrop'
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
        BigNumber.from(dateNow).add(86400)
    )

    await gameToken.increaseFund(gameAirdrop.address, bigNumber18.mul(1000));

    return { gameToken, gameAirdrop }
}