import { Wallet, BigNumber } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameToken } from '../typechain/GameToken'
import { GameSchedualPool } from '../typechain/GameSchedualPool'
import { expect } from './shared/expect'
import { gameSchedualPoolFixture, bigNumber18 } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GameTicket', async () => {
    let wallet: Wallet, other: Wallet;

    let depositToken: TestToken;
    let rewardToken: GameToken;
    let pool: GameSchedualPool;

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, other] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet, other])
    })

    beforeEach('deploy GameTicket', async () => {
        ; ({ depositToken, rewardToken, pool } = await loadFixTure(gameSchedualPoolFixture));
        await depositToken.approve(pool.address, ethers.constants.MaxUint256)  
        await pool.batchUpdateLockWeights(
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
        it('success for LockCreated emit', async () => {
            expect(await pool.createLock(bigNumber18.mul(100), BigNumber.from(1))).to.emit(pool, 'LockCreated')
        })
    })
 
    describe('#increaseAmount', async () => {

    })

    describe('#increaseUnlockTime', async () => {

    })

    describe('#totalSupply', async () => {

    })

    describe('#balanceOf', async () => {

    })

    describe('#pendingReward', async () => {

    })

    describe('#harvest', async () => {

    })

    describe('#withdraw', async () => {

    })
})