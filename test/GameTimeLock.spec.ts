import { Wallet, BigNumber } from 'ethers'
import { ethers, network, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameTimeLock } from '../typechain/GameTimeLock'
import { expect } from './shared/expect'
import { gameTimeLockFixture, bigNumber18 } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GameTimeLock', async () => {
    let wallet: Wallet, other: Wallet;


    let lockToken: TestToken
    let gameTimeLock: GameTimeLock

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, other] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet])
    })

    beforeEach('deploy GameTimeLock', async () => {
        ; ({ lockToken, gameTimeLock } = await loadFixTure(gameTimeLockFixture));
        await gameTimeLock.setFarmList([wallet.address])
        expect(await gameTimeLock.farms(wallet.address)).to.eq(true)
    })

    describe('#lock', async () => {
        it('success for first lock', async () => {
            lockToken.transfer(gameTimeLock.address, bigNumber18.mul(100))
            await gameTimeLock.lock(wallet.address, bigNumber18.mul(100))
            let lockInfo = await gameTimeLock.getLockInfo(wallet.address)
            expect(lockInfo.lockedAmount).to.eq(bigNumber18.mul(100))
            expect(lockInfo.debt).to.eq(0)
            expect(lockInfo.accReleasedPerBlock).to.eq(bigNumber18.mul(20))
        })

        it('success for lock again over time', async () => {
            // first lock 
            lockToken.transfer(gameTimeLock.address, bigNumber18.mul(100))
            await gameTimeLock.lock(other.address, bigNumber18.mul(100))
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
            // second lock
            let balanceBefore = await lockToken.balanceOf(other.address)
            lockToken.transfer(gameTimeLock.address, bigNumber18.mul(100))
            await gameTimeLock.lock(other.address, bigNumber18.mul(100))
            let balanceAfter = await lockToken.balanceOf(other.address)
            expect(balanceAfter.sub(balanceBefore)).to.eq(bigNumber18.mul(100))
            let lockInfo = await gameTimeLock.getLockInfo(other.address)
            expect(lockInfo.lockedAmount).to.eq(bigNumber18.mul(100))
            expect(lockInfo.debt).to.eq(0)
            expect(lockInfo.accReleasedPerBlock).to.eq(bigNumber18.mul(20))
        })

        it('success for lock again in time', async () => {
            // first lock 
            lockToken.transfer(gameTimeLock.address, bigNumber18.mul(100))
            await gameTimeLock.lock(other.address, bigNumber18.mul(100))
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
            // second lock
            let balanceBefore = await lockToken.balanceOf(other.address)
            lockToken.transfer(gameTimeLock.address, bigNumber18.mul(100))
            await gameTimeLock.lock(other.address, bigNumber18.mul(100))
            let balanceAfter = await lockToken.balanceOf(other.address)
            expect(balanceAfter.sub(balanceBefore)).to.eq(bigNumber18.mul(80))
            let lockInfo = await gameTimeLock.getLockInfo(other.address)
            expect(lockInfo.lockedAmount).to.eq(bigNumber18.mul(120))
            expect(lockInfo.debt).to.eq(0)
            expect(lockInfo.accReleasedPerBlock).to.eq(bigNumber18.mul(24))
        })

        it('gas used', async () => {
            // first lock 
            lockToken.transfer(gameTimeLock.address, bigNumber18.mul(100))
            let tx = await gameTimeLock.lock(other.address, bigNumber18.mul(100))
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(12_1962)
        })
    })

    describe('#getPendingAmount', async () => {
        beforeEach('create lock', async () => {
            lockToken.transfer(gameTimeLock.address, bigNumber18.mul(100))
            await gameTimeLock.lock(other.address, bigNumber18.mul(100))
        })

        it('success for only lock', async () => {
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
            expect(await gameTimeLock.getPendingAmount(other.address)).to.eq(bigNumber18.mul(40))
        })

        it('success for lock and claim', async () => {
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
            await gameTimeLock.connect(other).claim()
            await network.provider.send('evm_mine')
            expect(await gameTimeLock.getPendingAmount(other.address)).to.eq(bigNumber18.mul(20))
            let lockInfo = await gameTimeLock.getLockInfo(other.address)
            expect(lockInfo.debt).to.eq(bigNumber18.mul(60))
        })
    })

    describe('#claim', async () => {
        beforeEach('create lock', async () => {
            lockToken.transfer(gameTimeLock.address, bigNumber18.mul(100))
            await gameTimeLock.lock(other.address, bigNumber18.mul(100))
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
        })

        it('success for repetitive claim', async () => {
            await network.provider.send('evm_mine')
            await network.provider.send('evm_mine')
            await gameTimeLock.connect(other).claim()
            expect(await gameTimeLock.connect(other).claim()).to.emit(gameTimeLock, 'Claim').withArgs(other.address, BigNumber.from(0))
        })

        it('gas used', async () => {
            let tx = await gameTimeLock.connect(other).claim()
            let receipt = await tx.wait()
            expect(receipt.gasUsed).to.eq(9_5634)
        })
    })
})