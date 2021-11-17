import { Wallet, BigNumber } from 'ethers'
import { ethers, network, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameToken } from '../typechain/GameToken'
import { GameFarm } from '../typechain/GameFarm'
import { expect } from './shared/expect'
import { gameFarmFixture, bigNumber18 } from './shared/fixtures'
import { MockContract } from '@ethereum-waffle/mock-contract'

const createFixtureLoader = waffle.createFixtureLoader

describe('GameSchedualPool', async () => {
    let wallet: Wallet, other: Wallet;

    let depositToken1: TestToken
    let depositToken2: TestToken
    let rewardToken: GameToken
    let gameTimeLock: MockContract
    let farm: GameFarm

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, other] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet, other])
    })

    beforeEach('deploy GameSchedualPool', async () => {
        ; ({ depositToken1, rewardToken, gameTimeLock, farm } = await loadFixTure(gameFarmFixture));
        await farm.add(true, BigNumber.from(1), depositToken1.address)
        expect(await farm.poolExistence(depositToken1.address)).to.eq(true)
    })

    describe('#deposit', async () => {
        it('fails for not exist pool', async () => {
            await expect(farm.deposit(BigNumber.from(1), bigNumber18.mul(50), wallet.address)).to.reverted
        })

        it('success for first deposit', async () => {
            await farm.deposit(BigNumber.from(0), bigNumber18.mul(50), wallet.address)
            let userInfo = await farm.userInfo(BigNumber.from(0), wallet.address)
            expect(userInfo.amount).to.eq(bigNumber18.mul(50))
            expect(userInfo.rewardDebt).to.eq(BigNumber.from(0))
        })

        it('success for repetitive deposit', async () => {
            await farm.deposit(BigNumber.from(0), bigNumber18.mul(50), wallet.address)
            let rewardBalanceBefore = await rewardToken.balanceOf(wallet.address)
            await farm.deposit(BigNumber.from(0), bigNumber18.mul(50), wallet.address)
            let rewardBalanceAfter = await rewardToken.balanceOf(wallet.address)
            expect(rewardBalanceAfter.sub(rewardBalanceBefore)).to.eq(bigNumber18.mul(10))
            let userInfo = await farm.userInfo(BigNumber.from(0), wallet.address)
            expect(userInfo.amount).to.eq(bigNumber18.mul(100))
            expect(userInfo.rewardDebt).to.eq(bigNumber18.mul(20))
        })

        it('success for two deposit', async () => {
            await farm.deposit(BigNumber.from(0), bigNumber18.mul(50), wallet.address)
            await farm.connect(other).deposit(BigNumber.from(0), bigNumber18.mul(50), other.address)
            await network.provider.send('evm_mine')
            expect(await farm.pendingReward(BigNumber.from(0), wallet.address)).to.eq(bigNumber18.mul(15))
            expect(await farm.pendingReward(BigNumber.from(0), other.address)).to.eq(bigNumber18.mul(5))
        })

        it('gas used', async () => {
            let tx = await farm.deposit(BigNumber.from(0), bigNumber18.mul(50), wallet.address)
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(14_3486)
        })
    })

    describe('#harvest', async () => {
        beforeEach('deposit', async () => {
            await farm.deposit(BigNumber.from(0), bigNumber18.mul(50), wallet.address)
            await network.provider.send('evm_mine')
        })

        it('success for first harvest', async () => {
            expect(await farm.pendingReward(BigNumber.from(0), wallet.address)).to.eq(bigNumber18.mul(10))
            let rewardBalanceBefore = await rewardToken.balanceOf(wallet.address)
            await farm.harvest(BigNumber.from(0), wallet.address)
            let rewardBalanceAfter = await rewardToken.balanceOf(wallet.address)
            expect(rewardBalanceAfter.sub(rewardBalanceBefore)).to.eq(bigNumber18.mul(20))
        })

        it('success for repetitive harvest', async () => {
            await farm.harvest(BigNumber.from(0), wallet.address)
            await farm.harvest(BigNumber.from(0), wallet.address)
            let userInfo = await farm.userInfo(BigNumber.from(0), wallet.address)
            expect(userInfo.amount).to.eq(bigNumber18.mul(50))
            expect(userInfo.rewardDebt).to.eq(bigNumber18.mul(30))
        })

        it('success for harvest rate 0.3', async () => {
            await farm.setHarvestRate(30);
            expect(await farm.pendingReward(BigNumber.from(0), wallet.address)).to.eq(bigNumber18.mul(20))
            let rewardBalanceBefore = await rewardToken.balanceOf(gameTimeLock.address)
            await farm.harvest(BigNumber.from(0), wallet.address)
            let rewardBalanceAfter = await rewardToken.balanceOf(gameTimeLock.address)
            expect(rewardBalanceAfter.sub(rewardBalanceBefore)).to.eq(bigNumber18.mul(21))
        })

        it('gas used', async () => {
            let tx = await farm.harvest(BigNumber.from(0), wallet.address)
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(17_0000)
        })
    })

    describe('#withdraw', async () => {
        beforeEach('deposit', async () => {
            await farm.connect(other).deposit(BigNumber.from(0), bigNumber18.mul(100), wallet.address)
            await network.provider.send('evm_mine')
        })

        it('success', async () => {
            let rewardBalanceBefore = await rewardToken.balanceOf(other.address)
            let depositBalanceBefore = await depositToken1.balanceOf(other.address)
            await farm.withdraw(BigNumber.from(0), bigNumber18.mul(100), other.address)
            let rewardBalanceAfter = await rewardToken.balanceOf(other.address)
            let depositBalanceAfter = await depositToken1.balanceOf(other.address)
            expect(rewardBalanceAfter.sub(rewardBalanceBefore)).to.eq(bigNumber18.mul(20))
            expect(depositBalanceAfter.sub(depositBalanceBefore)).to.eq(bigNumber18.mul(100))
        })

        it('gas used', async () => {
            let tx = await farm.withdraw(BigNumber.from(0), bigNumber18.mul(100), other.address)
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(20_2682)
        })
    })
})