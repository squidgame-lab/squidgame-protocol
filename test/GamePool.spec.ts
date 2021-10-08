import { Wallet, BigNumber } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameTicket } from '../typechain/GameTicket'
import { GameConfig } from '../typechain/GameConfig'
import { GameToken } from '../typechain/gameToken'
import { GamePool } from '../typechain/GamePool'
import { expect } from './shared/expect'
import { gamePoolFixture, OneInDecimals } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GamePool', async () => {
    let wallet: Wallet, other: Wallet;

    let buyToken: TestToken;
    let gameTicket: GameTicket;
    let gameConfig: GameConfig;
    let gameToken: GameToken
    let gamePoolDay: GamePool
    let gamePoolWeek: GamePool

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, other] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet, other])
    })

    beforeEach('deploy GamePool', async () => {
        ; ({ buyToken, gameTicket, gameConfig, gameToken, gamePoolDay, gamePoolWeek } = await loadFixTure(gamePoolFixture));
        await buyToken.mint(wallet.address, OneInDecimals.mul(10000));
    })

    describe('setNexPoolRate', async () => {
        it('success for right nextPoolRate', async () => {
            expect(await gamePoolDay.nextPoolRate()).to.eq(5);
            expect(await gamePoolWeek.nextPoolRate()).to.eq(5);
        })
    })
})