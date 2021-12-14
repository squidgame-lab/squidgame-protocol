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
import { gameTicketExchangeFixture, bigNumber18, bigNumber17, deadline } from './shared/fixtures'

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

    describe('#batchSetLevelTicket', async () => {
        it('success for level1 level2', async () => {
            expect(await gameTicketExchange.levelTickets(BigNumber.from(1))).to.eq(gameLevel1Ticket.address)
            expect(await gameTicketExchange.levelTickets(BigNumber.from(2))).to.eq(gameLevel2Ticket.address)
        })
    })

    describe('#getStatus', async () => {
        it('fails for not exist level info', async () => {
            await expect(gameTicketExchange.getStatus(BigNumber.from(3), wallet.address)).to.revertedWith('GameTicketExchange: LEVEL_NOT_EXIST')
        })

        it('success for new user', async () => {
            expect(await gameTicketExchange.getStatus(BigNumber.from(1), wallet.address)).to.eq(true)
            expect(await gameTicketExchange.getStatus(BigNumber.from(2), wallet.address)).to.eq(false)
        })

        it('success for level2 joined user', async () => {
            await gameLevel2Ticket.setStatus(wallet.address)
            expect(await gameTicketExchange.getStatus(BigNumber.from(2), wallet.address)).to.eq(true)
        })
    })

    describe('#getTicketsAmount', async () => {
        it('success for new user', async () => {
            expect(await gameTicketExchange.getTicketsAmount(BigNumber.from(1), wallet.address)).to.eq(BigNumber.from(0))
            expect(await gameTicketExchange.getTicketsAmount(BigNumber.from(2), wallet.address)).to.eq(BigNumber.from(0))
        })

        it('success for user', async () => {
            let ticketAmount = BigNumber.from(5)
            await gameLevel2Ticket.setTicketBalance(wallet.address, ticketAmount)
            expect(await gameTicketExchange.getTicketsAmount(BigNumber.from(2), wallet.address)).to.eq(ticketAmount)
        })
    })

    describe('#getPaymentAmount', async () => {
        it('success for busd as payment token in level1', async () => {
            let ticketAmount = BigNumber.from(10)
            let res = await gameTicketExchange.getPaymentAmount(BigNumber.from(1), ticketAmount, busd.address)
            expect(res).to.gt(bigNumber18.mul(ticketAmount))
            expect(res).to.lt(bigNumber18.mul(ticketAmount.add(1)))
        })

        it('success for weth as payment token in level1', async () => {
            let ticketAmount = BigNumber.from(100)
            let res = await gameTicketExchange.getPaymentAmount(BigNumber.from(1), ticketAmount, ethers.constants.AddressZero)
            expect(res).to.gt(bigNumber17.mul(10))
            expect(res).to.lt(bigNumber17.mul(11))
        })

        it('success for usdt as payment token in level1', async () => {
            let ticketAmount = BigNumber.from(100)
            let res = await gameTicketExchange.getPaymentAmount(BigNumber.from(1), ticketAmount, usdt.address)
            expect(res).to.eq(bigNumber18.mul(100))
        })

        it('success for sqt as payment token in level1', async () => {
            let ticketAmount = BigNumber.from(10)
            let res = await gameTicketExchange.getPaymentAmount(BigNumber.from(1), ticketAmount, sqt.address)
            expect(res).to.gt(bigNumber18.mul(100))
            expect(res).to.lt(bigNumber18.mul(102))
        })

        it('success for busd as payment token in level2', async () => {
            let ticketAmount = BigNumber.from(10)
            let res = await gameTicketExchange.getPaymentAmount(BigNumber.from(2), ticketAmount, busd.address)
            expect(res).to.gt(bigNumber18.mul(11))
            expect(res).to.lt(bigNumber18.mul(12))
        })

        it('success for weth as payment token in level2', async () => {
            let ticketAmount = BigNumber.from(100)
            let res = await gameTicketExchange.getPaymentAmount(BigNumber.from(2), ticketAmount, ethers.constants.AddressZero)
            expect(res).to.gt(bigNumber17.mul(11))
            expect(res).to.lt(bigNumber17.mul(12))
        })

        it('success for usdt as payment token in level2', async () => {
            let ticketAmount = BigNumber.from(10)
            let res = await gameTicketExchange.getPaymentAmount(BigNumber.from(2), ticketAmount, usdt.address)
            expect(res).to.gt(bigNumber18.mul(11))
            expect(res).to.lt(bigNumber18.mul(12))
        })

        it('success for sqt as payment token in level2', async () => {
            let ticketAmount = BigNumber.from(10)
            let res = await gameTicketExchange.getPaymentAmount(BigNumber.from(2), ticketAmount, sqt.address)
            expect(res).to.gt(bigNumber18.mul(110))
            expect(res).to.lt(bigNumber18.mul(112))
        })
    })

    describe('#buy', async () => {
        beforeEach('make account access', async () => {
            await gameLevel2Ticket.setStatus(other.address)
            await busd.transfer(other.address, bigNumber18.mul(100))
            await busd.connect(other).approve(gameTicketExchange.address, ethers.constants.MaxUint256)
            await usdt.transfer(other.address, bigNumber18.mul(100))
            await usdt.connect(other).approve(gameTicketExchange.address, ethers.constants.MaxUint256)        })

        it('success for busd as payment token in level1', async () => {
            let ticketAmount = BigNumber.from(10)
            let estimatedAmount = await gameTicketExchange.getPaymentAmount(BigNumber.from(1), ticketAmount, busd.address)
            let balanceBefore = await busd.balanceOf(other.address);
            await gameTicketExchange.connect(other).buy(BigNumber.from(1), ticketAmount, busd.address, estimatedAmount, deadline)
            let balanceAfter = await busd.balanceOf(other.address);
            expect(balanceBefore.sub(balanceAfter)).to.eq(estimatedAmount)
            expect(await gameTicketExchange.getTicketsAmount(BigNumber.from(1), other.address)).to.eq(bigNumber18.mul(ticketAmount))
        })

        it('success for weth as payment token in level1', async () => {
            let ticketAmount = BigNumber.from(100)
            let estimatedAmount = await gameTicketExchange.getPaymentAmount(BigNumber.from(1), ticketAmount, ethers.constants.AddressZero)
            await gameTicketExchange.connect(other).buy(BigNumber.from(1), ticketAmount, ethers.constants.AddressZero, estimatedAmount, deadline, { value: estimatedAmount })
            expect(await gameTicketExchange.getTicketsAmount(BigNumber.from(1), other.address)).to.eq(bigNumber18.mul(ticketAmount))
        })

        it('success for usdt as payment token in level1', async () => {
            let ticketAmount = BigNumber.from(10)
            let estimatedAmount = await gameTicketExchange.getPaymentAmount(BigNumber.from(1), ticketAmount, usdt.address)
            let balanceBefore = await usdt.balanceOf(other.address);
            await gameTicketExchange.connect(other).buy(BigNumber.from(1), ticketAmount, usdt.address, estimatedAmount, deadline)
            let balanceAfter = await usdt.balanceOf(other.address);
            expect(balanceBefore.sub(balanceAfter)).to.eq(estimatedAmount)
            expect(await gameTicketExchange.getTicketsAmount(BigNumber.from(1), other.address)).to.eq(bigNumber18.mul(ticketAmount))
        })

        it('success for busd as payment token in level2', async () => {
            let ticketAmount = BigNumber.from(10)
            let estimatedAmount = await gameTicketExchange.getPaymentAmount(BigNumber.from(2), ticketAmount, busd.address)
            let balanceBefore = await busd.balanceOf(other.address);
            await gameTicketExchange.connect(other).buy(BigNumber.from(2), ticketAmount, busd.address, estimatedAmount, deadline)
            let balanceAfter = await busd.balanceOf(other.address);
            expect(balanceBefore.sub(balanceAfter)).to.eq(estimatedAmount)
            expect(await gameTicketExchange.getTicketsAmount(BigNumber.from(2), other.address)).to.eq(bigNumber18.mul(ticketAmount))
        })

        it('success for weth as payment token in level2', async () => {
            let ticketAmount = BigNumber.from(100)
            let estimatedAmount = await gameTicketExchange.getPaymentAmount(BigNumber.from(2), ticketAmount, ethers.constants.AddressZero)
            await gameTicketExchange.connect(other).buy(BigNumber.from(2), ticketAmount, ethers.constants.AddressZero, estimatedAmount, deadline, { value: estimatedAmount })
            expect(await gameTicketExchange.getTicketsAmount(BigNumber.from(2), other.address)).to.eq(bigNumber18.mul(ticketAmount))
        })

        it('success for usdt as payment token in level2', async () => {
            let ticketAmount = BigNumber.from(10)
            let estimatedAmount = await gameTicketExchange.getPaymentAmount(BigNumber.from(2), ticketAmount, usdt.address)
            let balanceBefore = await usdt.balanceOf(other.address);
            await gameTicketExchange.connect(other).buy(BigNumber.from(2), ticketAmount, usdt.address, estimatedAmount, deadline)
            let balanceAfter = await usdt.balanceOf(other.address);
            expect(balanceBefore.sub(balanceAfter)).to.eq(estimatedAmount)
            expect(await gameTicketExchange.getTicketsAmount(BigNumber.from(2), other.address)).to.eq(bigNumber18.mul(ticketAmount))
        })

        it('gas used for busd payment token in level1', async () => {
            let ticketAmount = BigNumber.from(10)
            let estimatedAmount = await gameTicketExchange.getPaymentAmount(BigNumber.from(1), ticketAmount, busd.address)
            let tx = await gameTicketExchange.connect(other).buy(BigNumber.from(1), ticketAmount, busd.address, estimatedAmount, deadline)
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(BigNumber.from(300850))
        })

        it('gas used for weth payment token in level1', async () => {
            let ticketAmount = BigNumber.from(100)
            let estimatedAmount = await gameTicketExchange.getPaymentAmount(BigNumber.from(1), ticketAmount, ethers.constants.AddressZero)
            let tx = await gameTicketExchange.connect(other).buy(BigNumber.from(1), ticketAmount, ethers.constants.AddressZero, estimatedAmount, deadline, { value: estimatedAmount })
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(BigNumber.from(297152))
        })

        it('gas used for busd as payment token in level2', async () => {
            let ticketAmount = BigNumber.from(10)
            let estimatedAmount = await gameTicketExchange.getPaymentAmount(BigNumber.from(2), ticketAmount, busd.address)
            let tx = await gameTicketExchange.connect(other).buy(BigNumber.from(2), ticketAmount, busd.address, estimatedAmount, deadline)
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(BigNumber.from(489047))
        })

        it('gas used for weth as payment token in level2', async () => {
            let ticketAmount = BigNumber.from(100)
            let estimatedAmount = await gameTicketExchange.getPaymentAmount(BigNumber.from(2), ticketAmount, ethers.constants.AddressZero)
            let tx = await gameTicketExchange.connect(other).buy(BigNumber.from(2), ticketAmount, ethers.constants.AddressZero, estimatedAmount, deadline, { value: estimatedAmount })
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(BigNumber.from(485348))
        })
    })
})