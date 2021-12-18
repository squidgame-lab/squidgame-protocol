import { Wallet, BigNumber } from 'ethers'
import { ethers, network, waffle } from 'hardhat'
import { GameToken } from '../typechain/GameToken'
import { GamePrediction } from '../typechain/GamePrediction'
import { expect } from './shared/expect'
import { gamePredictionFixture, bigNumber18, bigNumber17 } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GamePrediction', async () => {
    let wallet: Wallet, user1: Wallet, user2: Wallet, user3: Wallet, user4: Wallet;

    let sqt: GameToken
    let gamePrediction: GamePrediction

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, user1, user2, user3, user4] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet])
    })

    beforeEach('deploy GamePrediction', async () => {
        ; ({ sqt, gamePrediction } = await loadFixTure(gamePredictionFixture));
        await sqt.transfer(user1.address, bigNumber18.mul(100));
        await sqt.transfer(user2.address, bigNumber18.mul(100));
        await sqt.transfer(user3.address, bigNumber18.mul(100));
        await sqt.transfer(user4.address, bigNumber18.mul(100));
        await sqt.connect(user1).approve(gamePrediction.address, ethers.constants.MaxUint256)
        await sqt.connect(user2).approve(gamePrediction.address, ethers.constants.MaxUint256)
        await sqt.connect(user3).approve(gamePrediction.address, ethers.constants.MaxUint256)
        await sqt.connect(user4).approve(gamePrediction.address, ethers.constants.MaxUint256)
    })

    describe('#updateRound', async () => {
        it('reverted for wrong roundId', async () => {
            await expect(gamePrediction.updateRound(BigNumber.from(3), 0, 0, 0)).to.revertedWith('GamePrediction: INVALID_ROUNDID')
        })

        it('reverted for wrong max number', async () => {
            await expect(gamePrediction.updateRound(BigNumber.from(1), 4, 0, 0)).to.revertedWith('GamePrediction: INVALID_MAX_NUM')
        })

        it('reverted for wrong time', async () => {
            await network.provider.send('evm_increaseTime', [3000])
            await network.provider.send('evm_mine')
            await expect(gamePrediction.updateRound(BigNumber.from(1), 6, 0, 0)).to.revertedWith('GamePrediction: ROUND_EXPIRED')
        })

        it('success', async () => {
            let roundBefore = await gamePrediction.getRound(BigNumber.from(1))
            await gamePrediction.updateRound(
                BigNumber.from(1),
                BigNumber.from(6),
                (Date.now() / 1000 + 3000).toFixed(0),
                (Date.now() / 1000 + 4000).toFixed(0)
            )
            let roundAfter = await gamePrediction.getRound(BigNumber.from(1))
            expect(roundAfter.startTime).to.eq(roundBefore.startTime)
            expect(roundAfter.endTime).to.not.eq(roundBefore.endTime)
            expect(roundAfter.maxNumber).to.eq(BigNumber.from(6))
        })
    })

    describe('#predict', async () => {
        it('reverted for wrong time', async () => {
            await network.provider.send('evm_increaseTime', [3000])
            await network.provider.send('evm_mine')
            await expect(gamePrediction.predict(BigNumber.from(1), BigNumber.from(5), bigNumber18)).to.revertedWith('GamePrediction: WRONG_TIME')
        })

        it('success for predict round 1 num 1 first time', async () => {
            let roundId = BigNumber.from(1)
            let num = BigNumber.from(1)
            let amount = bigNumber18.mul(10)
            await gamePrediction.connect(user1).predict(roundId, num, amount)
            expect(await gamePrediction.getUserRoundOrderslength(roundId, user1.address)).to.eq(BigNumber.from(1))
            expect(await gamePrediction.getUserOrderslength(user1.address)).to.eq(BigNumber.from(1))
            let userOrders = await gamePrediction.getUserRoundOrders(roundId, user1.address, BigNumber.from(0), BigNumber.from(0))
            expect(userOrders.length).to.eq(BigNumber.from(1))
            expect(userOrders[0].orderId).to.eq(BigNumber.from(1))
            expect(userOrders[0].round).to.eq(roundId)
            expect(userOrders[0].number).to.eq(num)
            expect(userOrders[0].amount).to.eq(amount)
            expect(userOrders[0].user).to.eq(user1.address)
            let round = await gamePrediction.getRound(roundId)
            expect(round.totalAmount).to.eq(amount)
            expect(await gamePrediction.round2number2totalAmount(roundId, num)).to.eq(amount)
        })

        it('success for predict round 1 num 1 second time', async () => {
            let roundId = BigNumber.from(1)
            let num = BigNumber.from(1)
            let amount = bigNumber18.mul(10)
            await gamePrediction.connect(user1).predict(roundId, num, amount)
            await gamePrediction.connect(user1).predict(roundId, num, amount)
            expect(await gamePrediction.getUserRoundOrderslength(roundId, user1.address)).to.eq(BigNumber.from(1))
            expect(await gamePrediction.getUserOrderslength(user1.address)).to.eq(BigNumber.from(1))
            let userOrders = await gamePrediction.getUserRoundOrders(roundId, user1.address, BigNumber.from(0), BigNumber.from(0))
            expect(userOrders.length).to.eq(BigNumber.from(1))
            expect(userOrders[0].orderId).to.eq(BigNumber.from(1))
            expect(userOrders[0].round).to.eq(roundId)
            expect(userOrders[0].number).to.eq(num)
            expect(userOrders[0].amount).to.eq(amount.mul(2))
            expect(userOrders[0].user).to.eq(user1.address)
            let round = await gamePrediction.getRound(roundId)
            expect(round.totalAmount).to.eq(amount.mul(2))
            expect(await gamePrediction.round2number2totalAmount(roundId, num)).to.eq(amount.mul(2))
        })

        it('success for predict round 1 num 2 first time', async () => {
            let roundId = BigNumber.from(1)
            let num1 = BigNumber.from(1)
            let num2 = BigNumber.from(2)
            let amount = bigNumber18.mul(10)
            await gamePrediction.connect(user1).predict(roundId, num1, amount)
            await gamePrediction.connect(user1).predict(roundId, num2, amount)
            expect(await gamePrediction.getUserRoundOrderslength(roundId, user1.address)).to.eq(BigNumber.from(2))
        })

        it('success for predict round 2 num 1 first time', async () => {
            let roundId = BigNumber.from(2)
            let num1 = BigNumber.from(1)
            let amount = bigNumber18.mul(10)
            await gamePrediction.connect(user1).predict(roundId, num1, amount, { value: amount })
            expect(await gamePrediction.getUserRoundOrderslength(roundId, user1.address)).to.eq(BigNumber.from(1))
        })
    })

    describe('#setWinNumber', async () => {
        it('reverted for wrong win number', async () => {
            let roundId = BigNumber.from(1)
            let winNum = BigNumber.from(6)
            await expect(gamePrediction.setWinNumber(roundId, winNum)).to.revertedWith('GamePrediction: INVALID_WIN_NUMBER')
        })

        it('reverted for not finished round', async () => {
            let roundId = BigNumber.from(1)
            let winNum = BigNumber.from(1)
            await expect(gamePrediction.setWinNumber(roundId, winNum)).to.revertedWith('GamePrediction: ROUND_NOT_FINISHED')
        })

        it('success', async () => {
            let roundId = BigNumber.from(1)
            let num1 = BigNumber.from(1)
            let num2 = BigNumber.from(2)
            let amount = bigNumber18.mul(10)
            await gamePrediction.connect(user1).predict(roundId, num1, amount)
            await gamePrediction.connect(user2).predict(roundId, num2, amount)
            await network.provider.send('evm_increaseTime', [3000])
            await network.provider.send('evm_mine')
            await gamePrediction.setWinNumber(roundId, num1)
            let round = await gamePrediction.getRound(roundId)
            expect(round.totalAmount).to.eq(amount.mul(2))
            expect(round.accAmount).to.eq(BigNumber.from(2))
        })
    })

    describe('#getReward', async () => {
        beforeEach('predict', async () => {
            let roundId = BigNumber.from(1)
            let num1 = BigNumber.from(1)
            let num2 = BigNumber.from(2)
            let num3 = BigNumber.from(3)
            let num4 = BigNumber.from(4)
            let amount = bigNumber18.mul(10)
            await gamePrediction.connect(user1).predict(roundId, num1, amount)
            await gamePrediction.connect(user2).predict(roundId, num2, amount)
            await gamePrediction.connect(user3).predict(roundId, num3, amount)
            await gamePrediction.connect(user4).predict(roundId, num4, amount)
        })

        it('fails for no prediction user', async () => {

        })

        it('fails for not set winNumber', async () => {

        })

        it('fails for predicted num is not win number', async () => {

        })

        it('success for predicted num is win number', async () => {

        })
    })

    describe('#claim', async () => {
        beforeEach('predict', async () => {
            let roundId = BigNumber.from(1)
            let num1 = BigNumber.from(1)
            let num2 = BigNumber.from(2)
            let num3 = BigNumber.from(3)
            let num4 = BigNumber.from(4)
            let amount = bigNumber18.mul(10)
            await gamePrediction.connect(user1).predict(roundId, num1, amount)
            await gamePrediction.connect(user2).predict(roundId, num2, amount)
            await gamePrediction.connect(user3).predict(roundId, num3, amount)
            await gamePrediction.connect(user4).predict(roundId, num4, amount)
        })

        it('fails for no prediction user', async () => {

        })

        it('fails for not set winNumber', async () => {

        })

        it('fails for predicted num is not win number', async () => {

        })

        it('success for predicted num is win number', async () => {

        })

        it('fails for multi claim', async () => {

        })
    })
})