import { Wallet, BigNumber } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameTicket } from '../typechain/GameTicket'
import { GameConfig } from '../typechain/GameConfig'
import { GameToken } from '../typechain/gameToken'
import { GamePool } from '../typechain/GamePool'
import { expect } from './shared/expect'
import { gamePoolFixture, OneInDecimals, zeroAddress } from './shared/fixtures'
import exp from 'constants'

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

    describe('#setNexPoolRate', async () => {
        it('success for right nextPoolRate', async () => {
            expect(await gamePoolDay.nextPoolRate()).to.eq(5);
            expect(await gamePoolWeek.nextPoolRate()).to.eq(5);
        })

        it('success for set next pool rate', async () => {
            await gamePoolWeek.setNexPoolRate(BigNumber.from(0));
            expect(await gamePoolWeek.nextPoolRate()).to.eq(BigNumber.from(0));
        })
    })

    describe('#uploadOne', async () => {
        beforeEach('buy tickets', async () => {
            await buyToken.approve(gameTicket.address, OneInDecimals.mul('100000000'));
            await gameTicket.buy(OneInDecimals.mul(10), wallet.address);
        })

        it('fails for caller not manager', async () => {
            await expect(gamePoolDay.connect(other).uploadOne({
                user: wallet.address,
                ticketAmount: OneInDecimals.mul(5),
                winAmount: OneInDecimals.mul(5),
                claimed: false
            })).to.reverted
        })

        it('fails for zero user address', async () => {
            await expect(gamePoolDay.uploadOne({
                user: zeroAddress,
                ticketAmount: OneInDecimals.mul(5),
                winAmount: OneInDecimals.mul(5),
                claimed: false
            })).to.revertedWith('invalid param')
        })

        it('fails for over tickets amount', async () => {
            await expect(gamePoolDay.uploadOne({
                user: wallet.address,
                ticketAmount: OneInDecimals.mul(11),
                winAmount: OneInDecimals.mul(5),
                claimed: false
            })).to.revertedWith('ticket overflow')
        })

        it('success for case only one person join in game', async () => {
            await gamePoolDay.uploadOne({
                user: wallet.address,
                ticketAmount: OneInDecimals.mul(5),
                winAmount: OneInDecimals.mul(5),
                claimed: false
            })
            let totalRound = await gamePoolDay.totalRound();
            expect(await gamePoolDay.userRoundOrderMap(wallet.address, totalRound)).to.eq(BigNumber.from(0))
            expect(await gamePoolDay.userOrders(wallet.address, BigNumber.from(0))).to.eq(BigNumber.from(0));
            expect(await gamePoolDay.roundOrders(totalRound, BigNumber.from(0))).to.eq(BigNumber.from(0));
            let order = await gamePoolDay.orders(BigNumber.from(0));
            expect(order[0]).to.eq(BigNumber.from(0));
            expect(order[1]).to.eq(wallet.address);
            expect(await gamePoolDay.tickets(wallet.address)).to.eq(OneInDecimals.mul(5));
        })

        it('success for case one person multiple upload', async () => {
            await gamePoolDay.uploadOne({
                user: wallet.address,
                ticketAmount: OneInDecimals.mul(5),
                winAmount: OneInDecimals.mul(5),
                claimed: false
            })
            await gamePoolDay.uploadOne({
                user: wallet.address,
                ticketAmount: OneInDecimals.mul(5),
                winAmount: OneInDecimals.mul(5),
                claimed: false
            })
            let totalRound = await gamePoolDay.totalRound();
            expect(await gamePoolDay.userRoundOrderMap(wallet.address, totalRound)).to.eq(BigNumber.from(0))
            expect(await gamePoolDay.userOrders(wallet.address, BigNumber.from(0))).to.eq(BigNumber.from(0));
            expect(await gamePoolDay.roundOrders(totalRound, BigNumber.from(0))).to.eq(BigNumber.from(0));
            let order = await gamePoolDay.orders(BigNumber.from(0));
            expect(order[0]).to.eq(BigNumber.from(0));
            expect(order[1]).to.eq(wallet.address);
            expect(await gamePoolDay.tickets(wallet.address)).to.eq(OneInDecimals.mul(5));
        })
    })

    describe('#uploadBatch', async () => {
        beforeEach('buy tickets', async () => {
            await buyToken.approve(gameTicket.address, OneInDecimals.mul('100000000'));
            await gameTicket.buy(OneInDecimals.mul(10), wallet.address);
            await buyToken.transfer(other.address, OneInDecimals.mul(100))
            await buyToken.connect(other).approve(gameTicket.address, OneInDecimals.mul('100000000'));
            await gameTicket.connect(other).buy(OneInDecimals.mul(10), other.address);
        })

        it('fails for caller not manager', async () => {
            await expect(gamePoolDay.connect(other).uploadBatch([{
                user: wallet.address,
                ticketAmount: OneInDecimals.mul(5),
                winAmount: OneInDecimals.mul(5),
                claimed: false
            }])).to.reverted
        })

        it('success', async () => {
            await gamePoolDay.uploadBatch([
                {
                    user: wallet.address,
                    ticketAmount: OneInDecimals.mul(5),
                    winAmount: OneInDecimals.mul(10),
                    claimed: false
                },
                {
                    user: other.address,
                    ticketAmount: OneInDecimals.mul(5),
                    winAmount: OneInDecimals.mul(0),
                    claimed: false
                }
            ])
            let totalRound = await gamePoolDay.totalRound();
            expect(await gamePoolDay.roundOrders(totalRound, BigNumber.from(0))).to.eq(BigNumber.from(1));
        })
    })

    describe('#uploaded', async () => {
        beforeEach('upload results', async () => {
            await buyToken.approve(gameTicket.address, OneInDecimals.mul('100000000'));
            await gameTicket.buy(OneInDecimals.mul(10), wallet.address);
            await buyToken.transfer(other.address, OneInDecimals.mul(100))
            await buyToken.connect(other).approve(gameTicket.address, OneInDecimals.mul('100000000'));
            await gameTicket.connect(other).buy(OneInDecimals.mul(10), other.address);
            await gamePoolDay.uploadBatch([
                {
                    user: wallet.address,
                    ticketAmount: OneInDecimals.mul(5),
                    winAmount: OneInDecimals.mul(2),
                    claimed: false
                },
                {
                    user: other.address,
                    ticketAmount: OneInDecimals.mul(5),
                    winAmount: OneInDecimals.mul(0),
                    claimed: false
                }
            ])
        })

        it('fails for zero ticketTotal', async () => {
            await expect(gamePoolDay.uploaded(BigNumber.from(0), BigNumber.from(0), OneInDecimals, OneInDecimals)).to.revertedWith('zero');
        })

        it('success for first round', async () => {
            await gamePoolDay.uploaded(
                BigNumber.from(Date.now().toString()).div(1000),
                OneInDecimals.mul(10),
                OneInDecimals.mul(2),
                OneInDecimals.mul(10),
            );
            expect(await gamePoolDay.totalRound()).to.eq(1);
            expect(await buyToken.balanceOf(gamePoolDay.address)).to.eq(OneInDecimals.mul(8));
            expect(await buyToken.balanceOf(gamePoolWeek.address)).to.eq(OneInDecimals.mul(2));
        })
    })

    describe('canClaim', async () => {
        
    })
})