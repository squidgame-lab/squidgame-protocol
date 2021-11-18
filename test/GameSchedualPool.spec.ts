import { Wallet, BigNumber } from 'ethers'
import { ethers, network, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameToken } from '../typechain/GameToken'
import { GameSchedualPool } from '../typechain/GameSchedualPool'
import { expect } from './shared/expect'
import { gameSchedualPoolFixture, bigNumber18 } from './shared/fixtures'
import { MockContract } from '@ethereum-waffle/mock-contract'

const createFixtureLoader = waffle.createFixtureLoader

describe('GameSchedualPool', async () => {
    let wallet: Wallet, other: Wallet;

    let depositToken: TestToken;
    let rewardToken: GameToken;
    let gameTimeLock: MockContract
    let pool: GameSchedualPool;

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, other] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet, other])
    })

    beforeEach('deploy GameSchedualPool', async () => {
        ; ({ depositToken, rewardToken, gameTimeLock, pool } = await loadFixTure(gameSchedualPoolFixture));
        await depositToken.approve(pool.address, ethers.constants.MaxUint256)
        await depositToken.transfer(other.address, bigNumber18.mul(100))
        await depositToken.connect(other).approve(pool.address, ethers.constants.MaxUint256)
        await pool.batchSetLockWeights(
            [
                BigNumber.from(1),
                BigNumber.from(2),
                BigNumber.from(4)
            ],
            [
                BigNumber.from(100),
                BigNumber.from(100).mul(2),
                BigNumber.from(100).mul(4)
            ]
        )
        expect(await pool.lockWeights(BigNumber.from(1))).to.eq(BigNumber.from(100))
    })

    describe('#createLock', async () => {
        it('fails for wrong week count', async () => {
            await expect((pool.createLock(bigNumber18, BigNumber.from(3)))).to.revertedWith('GameSchedualPool: NOT_SUPPORT_WEEKCOUNT')
        })

        it('success for emit LockCreated', async () => {
            expect(await pool.createLock(bigNumber18.mul(100), BigNumber.from(1))).to.emit(pool, 'LockCreated')
        })

        it('success for one create lock', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            await network.provider.send('evm_mine')
            expect(await pool.pendingReward(wallet.address)).to.eq(bigNumber18.mul(10))
            expect(await pool.averageLockDur()).to.eq(10)
        })

        it('success for two create lock', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            await pool.connect(other).createLock(bigNumber18.mul(10), BigNumber.from(4))
            await network.provider.send('evm_mine')
            expect(await pool.pendingReward(wallet.address)).to.eq(bigNumber18.mul(12))
            expect(await pool.pendingReward(other.address)).to.eq(bigNumber18.mul(8))
            expect(await pool.averageLockDur()).to.eq(25)
        })

        it('fails for repetitive create lock', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            await expect(pool.createLock(bigNumber18.mul(10), BigNumber.from(1))).to.revertedWith('GameSchedualPool: EXIST_LOCK')
        })

        it('gas used', async () => {
            let tx = await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(26_1267)
        })
    })

    describe('#increaseAmount', async () => {
        it('fails for expire lock', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            await network.provider.send('evm_increaseTime', [86400 * 11])
            await network.provider.send('evm_mine')
            await expect(pool.increaseAmount(bigNumber18.fromTwos(10))).to.revertedWith('GameSchedualPool: EXPIRED_LOCK')
        })

        it('fails for not exist lock', async () => {
            await expect(pool.increaseAmount(bigNumber18.fromTwos(10))).to.revertedWith('GameSchedualPool: EXPIRED_LOCK')
        })

        it('success', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
            let rewardTokenBalanceBefore = await rewardToken.balanceOf(wallet.address)
            await pool.increaseAmount(bigNumber18.mul(10))
            let rewardTokenBalanceAfter = await rewardToken.balanceOf(wallet.address)
            expect(rewardTokenBalanceAfter.sub(rewardTokenBalanceBefore)).to.eq(bigNumber18.mul(30))
            let lockedBalance = await pool.locked(wallet.address)
            expect(lockedBalance.amount).to.eq(bigNumber18.mul(20))
            expect(lockedBalance.rewardDebt).to.eq(bigNumber18.mul(60))
            expect(await pool.averageLockDur()).to.eq(1 * 10)
        })

        it('emit', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            expect(await pool.increaseAmount(bigNumber18.mul(10))).to.emit(pool, 'AmountIncreased').withArgs(wallet.address, bigNumber18.mul(10))
        })

        it('gas used', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            let tx = await pool.increaseAmount(bigNumber18.mul(10))
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(21_5831)
        })
    })

    describe('#increaseUnlockTime', async () => {
        it('fails for expire lock', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            await network.provider.send('evm_increaseTime', [86400 * 11])
            await network.provider.send('evm_mine')
            await expect(pool.increaseUnlockTime(BigNumber.from(1))).to.revertedWith('GameSchedualPool: EXPIRED_LOCK')
        })

        it('fails for not exist lock', async () => {
            await expect(pool.increaseUnlockTime(BigNumber.from(1))).to.revertedWith('GameSchedualPool: EXPIRED_LOCK')
        })

        it('fails for invalid week count', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            await network.provider.send('evm_mine')
            await expect(pool.increaseUnlockTime(BigNumber.from(2))).to.revertedWith('GameSchedualPool: INVALID_WEEKCOUNT')
        })

        it('success', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
            let rewardTokenBalanceBefore = await rewardToken.balanceOf(wallet.address)
            await pool.increaseUnlockTime(BigNumber.from(1))
            let rewardTokenBalanceAfter = await rewardToken.balanceOf(wallet.address)
            expect(rewardTokenBalanceAfter.sub(rewardTokenBalanceBefore)).to.eq(bigNumber18.mul(30))
            let lockedBalance = await pool.locked(wallet.address)
            expect(lockedBalance.lockWeeks).to.eq(BigNumber.from(2))
            expect(lockedBalance.rewardDebt).to.eq(bigNumber18.mul(60))
            expect(await pool.averageLockDur()).to.eq(2 * 10)
        })

        it('emit', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            expect(await pool.increaseUnlockTime(BigNumber.from(1))).to.emit(pool, 'UnlockTimeIncreased')
        })

        it('gas used', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            let tx = await pool.increaseUnlockTime(BigNumber.from(1))
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(21_1356)
        })
    })

    describe('#harvest', async () => {
        beforeEach('create lock', async () => {
            await pool.createLock(bigNumber18.mul(10), BigNumber.from(1))
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
        })

        it('success for harvest rate 0', async () => {
            let rewardTokenBalanceBefore = await rewardToken.balanceOf(wallet.address)
            await pool.harvest(wallet.address)
            let rewardTokenBalanceAfter = await rewardToken.balanceOf(wallet.address)
            expect(rewardTokenBalanceAfter.sub(rewardTokenBalanceBefore)).to.eq(bigNumber18.mul(30))
        })

        it('success for harvest rate 0.3', async () => {
            await pool.setHarvestRate(BigNumber.from(30)) // mine block
            let walletRewardTokenBalanceBefore = await rewardToken.balanceOf(wallet.address)
            let timeLockRewardTokenBalanceBefore = await rewardToken.balanceOf(gameTimeLock.address)
            await pool.harvest(wallet.address) // mine block
            let walletRewardTokenBalanceAfter = await rewardToken.balanceOf(wallet.address)
            let timeLockRewardTokenBalanceAfter = await rewardToken.balanceOf(gameTimeLock.address)
            expect(walletRewardTokenBalanceAfter.sub(walletRewardTokenBalanceBefore)).to.eq(bigNumber18.mul(12))
            expect(timeLockRewardTokenBalanceAfter.sub(timeLockRewardTokenBalanceBefore)).to.eq(bigNumber18.mul(28))
        })

        it('emit', async () => {
            expect(await pool.harvest(wallet.address)).to.emit(pool, 'Harvest').withArgs(wallet.address, wallet.address, bigNumber18.mul(30))
        })

        it('gas used', async () => {
            let tx = await pool.harvest(wallet.address)
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(16_2194)
        })
    })

    describe('#withdraw', async () => {
        beforeEach('create lock', async () => {
            await pool.connect(other).createLock(bigNumber18.mul(10), BigNumber.from(1))
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
        })

        it('fails for unlock', async () => {
            await expect(pool.connect(other).withdraw()).to.revertedWith('GameSchedualPool: NOT_UNLOCK')
        })

        it('success', async () => {
            await network.provider.send('evm_increaseTime', [86400 * 11])
            await network.provider.send('evm_mine')
            let rewardBalanceBefore = await rewardToken.balanceOf(other.address)
            let depositBalanceBefore = await depositToken.balanceOf(other.address)
            await pool.connect(other).withdraw()
            let rewardBalanceAfter = await rewardToken.balanceOf(other.address)
            let depositBalanceAfter = await depositToken.balanceOf(other.address)
            expect(rewardBalanceAfter.sub(rewardBalanceBefore)).to.eq(bigNumber18.mul(40))
            expect(depositBalanceAfter.sub(depositBalanceBefore)).to.eq(bigNumber18.mul(10))
        })

        it('emit', async () => {
            await network.provider.send('evm_increaseTime', [86400 * 11])
            await network.provider.send('evm_mine')
            expect(await pool.connect(other).withdraw()).to.emit(pool, 'Withdraw').withArgs(other.address, bigNumber18.mul(10))
        })

        it('gas used', async () => {
            await network.provider.send('evm_increaseTime', [86400 * 11])
            await network.provider.send('evm_mine')
            let tx = await pool.connect(other).withdraw()
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(18_9857)
        })
    })
})