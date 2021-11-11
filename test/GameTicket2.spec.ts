import { Wallet, BigNumber } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameTicket2 } from '../typechain/GameTicket2'
import { GameToken } from '../typechain/GameToken'
import { expect } from './shared/expect'
import { bigNumber18 } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GameTicket2', async () => {
    let wallet: Wallet, other: Wallet;

    let buyToken: TestToken;
    let gameToken: GameToken;
    let gameTicket: GameTicket2;

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, other] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet, other])
    })

    beforeEach('deploy GameTicket', async () => {
        const gameTicketFactory = await ethers.getContractFactory('GameTicket2');
        const gameTokenFactory = await ethers.getContractFactory('GameToken');
        const testTokenFactory = await ethers.getContractFactory('TestToken')

        buyToken = (await testTokenFactory.deploy()) as TestToken
        await buyToken.initialize();

        gameToken = (await gameTokenFactory.deploy()) as GameToken;
        await gameToken.initialize();
        await gameToken.increaseFund(wallet.address,ethers.constants.MaxUint256);
        await gameToken.mint(wallet.address, bigNumber18.mul(10000));

        gameTicket = (await gameTicketFactory.deploy()) as GameTicket2;
        await gameTicket.initialize(buyToken.address, gameToken.address, bigNumber18, bigNumber18.mul(10), bigNumber18.mul(100));
        await buyToken.mint(wallet.address, bigNumber18.mul(10000));
    })

    describe('#join', async () => {
        beforeEach('approve gameToken to gameTicket', async () => {
            await gameToken.approve(gameTicket.address, ethers.constants.MaxUint256);
        })

        it('success for join', async () => {
            expect(await gameTicket.status(wallet.address)).to.equal(false);
            await gameTicket.join();
            expect(await gameTicket.status(wallet.address)).to.equal(true);
        })
    })

    describe('#buy', async () => {
        beforeEach('approve buyToken and gameToken to gameTicket', async () => {
            await buyToken.approve(gameTicket.address, ethers.constants.MaxUint256);
            await gameToken.approve(gameTicket.address, ethers.constants.MaxUint256);
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
            expect(await gameTicket.buy(bigNumber18.mul(2), wallet.address)).to.emit(gameTicket, 'Bought').withArgs(wallet.address, wallet.address, bigNumber18.mul(2), bigNumber18.mul(20));
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
            beforeEach('approve buyToken and gameToken to gameTicket', async () => {
                await buyToken.approve(gameTicket.address, ethers.constants.MaxUint256);
                await gameToken.approve(gameTicket.address, ethers.constants.MaxUint256);
            })
    
            beforeEach('buy', async () => {
                await gameTicket.setRewardPool(wallet.address);
                await gameTicket.buy(bigNumber18.mul(2), wallet.address);
            })

            it('success for zero fee', async () => {
                await gameTicket.withdraw(bigNumber18.mul(2));
                expect(await buyToken.balanceOf(wallet.address)).to.eq(bigNumber18.mul(10000));
            })

            it('success for 1% feeRate', async () => {
                await gameTicket.setFeeRate(100);
                let pool = await gameTicket.rewardPool();
                expect(await gameTicket.withdraw(bigNumber18.mul(2))).to.emit(gameTicket, 'Withdrawed').withArgs(pool, '1980000000000000000', wallet.address, '20000000000000000');
            })
        })
    })
})