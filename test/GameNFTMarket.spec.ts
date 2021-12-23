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

})