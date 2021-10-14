import { Wallet, BigNumber } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameTicket } from '../typechain/GameTicket'
import { GameConfig } from '../typechain/GameConfig'
import { expect } from './shared/expect'
import { gameTicketFixture, bigNumber18 } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GameTicket', async () => {
    let wallet: Wallet, other: Wallet;

    let buyToken: TestToken;
    let gameTicket: GameTicket;
    let gameConfig: GameConfig;

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, other] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet, other])
    })

    beforeEach('deploy GameTicket', async () => {
        ; ({ buyToken, gameTicket, gameConfig } = await loadFixTure(gameTicketFixture));
        await buyToken.mint(wallet.address, bigNumber18.mul(10000));
    })

    describe('#buy', async () => {
        beforeEach('approve buyToken to gameTicket', async () => {
            await buyToken.approve(gameTicket.address, ethers.constants.MaxUint256);
        })

        it('fails for zero value', async () => {
            await expect(gameTicket.buy(BigNumber.from(0), wallet.address)).to.revertedWith("GameTicket: ZERO");
        })

        it('fails for REMAINDER', async () => {
            await expect(gameTicket.buy(bigNumber18.add(1), wallet.address)).to.revertedWith('GameTicket: REMAINDER');
        })

        it('fails for INSUFFICIENT_BALANCE', async () => {
            await expect(gameTicket.connect(other).buy(bigNumber18, other.address)).to.revertedWith('GameTicket: INSUFFICIENT_BALANCE');
        })

        it('success for buy', async () => {
            await gameTicket.buy(bigNumber18.mul(2), wallet.address);
            expect(await gameTicket.tickets(wallet.address)).to.eq(bigNumber18.mul(2));
            expect(await gameTicket.total()).to.eq(bigNumber18.mul(2));
        })

        it('success for buy event', async () => {
            expect(await gameTicket.buy(bigNumber18.mul(2), wallet.address)).to.emit(gameTicket, 'Bought').withArgs(wallet.address, wallet.address, bigNumber18.mul(2));
        })
    })

    describe('#withdraw', async () => {
        describe('fails cases', async () => {
            it('fails for caller not rewardPool', async () => {
                await expect(gameTicket.withdraw(0)).to.revertedWith('GameTicket: FORBIDDEN');
            })

            it('false for balance not enough', async () => {
                await gameTicket.setRewardPool(wallet.address);
                await expect(gameTicket.withdraw(bigNumber18)).to.revertedWith('GameTicket: INSUFFICIENT_BALANCE');
            })
        })

        describe('success cases', async () => {
            beforeEach('buy', async () => {
                await gameTicket.setRewardPool(wallet.address);
                await buyToken.approve(gameTicket.address, bigNumber18.mul(10000));
                await gameTicket.buy(bigNumber18.mul(2), wallet.address);
            })

            it('success for zero fee', async () => {
                await gameTicket.withdraw(bigNumber18.mul(2));
                expect(await buyToken.balanceOf(wallet.address)).to.eq(bigNumber18.mul(10000));
            })

            it('success for 1% feeRate', async () => {
                await gameTicket.setFeeRate(100);
                await gameConfig.changeTeam(other.address);
                await gameTicket.withdraw(bigNumber18.mul(2));
                expect(await buyToken.balanceOf(wallet.address)).to.eq(bigNumber18.mul(10000).sub("20000000000000000"));
            })
        })
    })
})