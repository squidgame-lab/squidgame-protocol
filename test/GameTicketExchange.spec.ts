import { Wallet, BigNumber } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameToken } from '../typechain/GameToken'
import { WETH9 } from '../typechain/WETH9'
import { GameTicket } from '../typechain/GameTicket'
import { MockGameTicket } from '../typechain/MockGameTicket'
import { PancakeFactory } from '../typechain/PancakeFactory'
import { PancakeRouter } from '../typechain/PancakeRouter'
import { GameTicketExchange } from '../typechain/GameTicketExchange'
import { expect } from './shared/expect'
import { gameTicketExchangeFixture, bigNumber18 } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GameTicketExchange', async () => {
    let wallet: Wallet, other: Wallet;

    let usdt: TestToken
    let busd: TestToken
    let sqt: GameToken
    let weth: WETH9
    let gameLevel1Ticket: GameTicket
    let gameLevel2Ticket: MockGameTicket
    let pancakefactory: PancakeFactory
    let pancakeRouter: PancakeRouter
    let gameTicketExchange: GameTicketExchange

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, other] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet, other])
    })

    beforeEach('deploy GameTicketExchange', async () => {
        ; ({ usdt, busd, sqt, weth, gameLevel1Ticket, gameLevel2Ticket, factory: pancakefactory, pancakeRouter, gameTicketExchange } = await loadFixTure(gameTicketExchangeFixture));
    })

    it('check pancake router', async () => {
        expect(await pancakefactory.getPair(busd.address, usdt.address)).to.not.eq(ethers.constants.AddressZero)
        expect(await pancakefactory.getPair(sqt.address, usdt.address)).to.not.eq(ethers.constants.AddressZero)
        expect(await pancakefactory.getPair(weth.address, usdt.address)).to.not.eq(ethers.constants.AddressZero)
    })
})