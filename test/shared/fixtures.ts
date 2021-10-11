import { BigNumber } from 'ethers'
import { ethers } from 'hardhat'
import { TestToken } from '../../typechain/TestToken'
import { GameTicket } from '../../typechain/GameTicket'
import { GameConfig } from '../../typechain/GameConfig'
import { GamePool } from '../../typechain/GamePool'
import { GameToken } from '../../typechain/GameToken'
import { Fixture } from 'ethereum-waffle'

export const zeroAddress = "0x0000000000000000000000000000000000000000"
export const OneInDecimals = BigNumber.from("1000000000000000000")

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
    await gameTicket.initialize(buyToken.address, OneInDecimals);
    await gameTicket.setupConfig(gameConfig.address);

    return { buyToken, gameTicket, gameConfig };
}

interface GameConfigFixture extends GameTicketFixture {
    gameToken: GameToken
    gamePoolDay: GamePool
    gamePoolWeek: GamePool
}

export const gamePoolFixture: Fixture<GameConfigFixture> = async function (): Promise<GameConfigFixture> {
    const { buyToken, gameTicket, gameConfig } = await _gameTicketFixture();

    const gameTokenFactory = await ethers.getContractFactory('GameToken');
    const gamePoolFactory = await ethers.getContractFactory('GamePool');

    const gameToken = (await gameTokenFactory.deploy()) as GameToken;
    await gameToken.initialize();
    const gamePoolDay = (await gamePoolFactory.deploy()) as GamePool;
    await gamePoolDay.initialize();
    const gamePoolWeek = (await gamePoolFactory.deploy()) as GamePool;
    await gamePoolWeek.initialize()

    await gameToken.increaseFunds([gamePoolDay.address, gamePoolWeek.address], [OneInDecimals.mul(100000000), OneInDecimals.mul(100000000)])
    await gamePoolDay.configure(
        gameTicket.address,
        gameToken.address,
        gamePoolWeek.address,
        5,
        30,
        true
    );
    await gamePoolWeek.configure(
        gamePoolDay.address,
        gameToken.address,
        zeroAddress,
        5,
        60,
        false
    );
    await gameTicket.setRewardPool(gamePoolDay.address);

    return { buyToken, gameTicket, gameConfig, gameToken, gamePoolDay, gamePoolWeek };
}