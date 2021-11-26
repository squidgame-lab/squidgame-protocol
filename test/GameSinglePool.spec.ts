import { Wallet, BigNumber } from 'ethers'
import { ethers, network, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameToken } from '../typechain/GameToken'
import { GameSinglePool } from '../typechain/GameSinglePool'
import { expect } from './shared/expect'
import { gameSinglePoolFixture, bigNumber18 } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GameSinglePool', async () => {
    let wallet: Wallet, other: Wallet, blockHole: Wallet;

    let depositToken: TestToken
    let rewardToken: GameToken
    let pool: GameSinglePool

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, other, blockHole] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet, other])
    })

    beforeEach('deploy GameSinglePool', async () => {
        ; ({ depositToken, rewardToken, pool } = await loadFixTure(gameSinglePoolFixture));
    })

    describe('#deposit', async () => {
        it('success for first deposit', async () => {
            await pool.connect(other).deposit(bigNumber18.mul(10), other.address)
            let userInfo = await pool.userInfo(other.address)
            expect(userInfo.amount).to.eq(bigNumber18.mul(10))
            let now = (Date.now() / 1000).toFixed()
            expect(userInfo.unlockTime.sub(now)).to.gt(604790)
            expect(userInfo.unlockTime.sub(now)).to.lt(604810)
            expect(userInfo.rewardDebt).to.eq(BigNumber.from(0))
        })

        it('success for first depost reward info', async () => {
            await pool.connect(other).deposit(bigNumber18.mul(10), other.address)
            await network.provider.send('evm_mine')
            expect(await pool.pendingReward(other.address)).eq(bigNumber18.mul(10))
        })

        it('success for no reward', async () => {
            await pool.connect(other).deposit(bigNumber18.mul(10), other.address)
            await rewardToken.transfer(blockHole.address, bigNumber18.mul(1000))
            expect(await pool.pendingReward(other.address)).eq(bigNumber18.mul(0))
        })

        it('success for not enough reward', async () => {
            await pool.connect(other).deposit(bigNumber18.mul(10), other.address)
            await rewardToken.transfer(blockHole.address, bigNumber18.mul(995))
            expect(await pool.pendingReward(other.address)).eq(bigNumber18.mul(5))
        })

        it('success for repeat deposit in lock time', async () => {
            await pool.connect(other).deposit(bigNumber18.mul(10), other.address)
            await network.provider.send('evm_mine')
            let balanceBefore = await rewardToken.balanceOf(other.address)
            await pool.connect(other).deposit(bigNumber18.mul(10), other.address)
            let balanceAfter = await rewardToken.balanceOf(other.address)
            expect(balanceAfter.sub(balanceBefore)).to.eq(bigNumber18.mul(20))
            let userInfo = await pool.userInfo(other.address)
            expect(userInfo.amount).to.eq(bigNumber18.mul(20))
            let now = (Date.now() / 1000).toFixed()
            expect(userInfo.unlockTime.sub(now)).to.gt(604800 - 5)
            expect(userInfo.unlockTime.sub(now)).to.lt(604800 + 5)
        })

        it('success for repeat deposit over lock time', async () => {
            await pool.connect(other).deposit(bigNumber18.mul(10), other.address)
            await network.provider.send('evm_mine')
            let depositBalanceBefore = await depositToken.balanceOf(other.address)
            let balanceBefore = await rewardToken.balanceOf(other.address)
            await network.provider.send('evm_increaseTime', [604800])
            await pool.connect(other).deposit(bigNumber18.mul(10), other.address)
            let depositBalanceAfter = await depositToken.balanceOf(other.address)
            let balanceAfter = await rewardToken.balanceOf(other.address)
            expect(depositBalanceAfter.sub(depositBalanceBefore)).to.eq(BigNumber.from(0))
            expect(balanceAfter.sub(balanceBefore)).to.eq(bigNumber18.mul(20))
            let userInfo = await pool.userInfo(other.address)
            expect(userInfo.amount).to.eq(bigNumber18.mul(10))
            let now = (Date.now() / 1000).toFixed()
            expect(userInfo.unlockTime.sub(now)).to.gt(604800 * 2 - 5)
            expect(userInfo.unlockTime.sub(now)).to.lt(604800 * 2 + 5)
        })

        it('gas used', async () => {
            let tx = await pool.connect(other).deposit(bigNumber18.mul(10), other.address)
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(15_0478)
        })
    })

    describe('#harvest', async () => {

    })

    describe('#withdraw', async () => {

    })
})