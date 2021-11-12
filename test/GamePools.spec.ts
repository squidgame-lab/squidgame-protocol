import { Wallet, BigNumber } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameTicket } from '../typechain/GameTicket'
import { GameTicket2 } from '../typechain/GameTicket2'
import { GamePool } from '../typechain/GamePool'
import { GamePoolActivity } from '../typechain/GamePoolActivity'
import { GamePoolCS } from '../typechain/GamePoolCS'
import { GameToken } from '../typechain/GameToken'
import { expect } from './shared/expect'

import { gamePoolsFixture, bigNumber18 } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GamePools', async () => {
    let wallet: Wallet, user1: Wallet, user2: Wallet;

    let buyToken: TestToken;
    let gameToken: GameToken;
    let gameTicket: GameTicket;
    let gameTicket2: GameTicket2;
    let gamePool: GamePool;
    let gamePoolActivity: GamePoolActivity;
    let gamePoolCS: GamePoolCS;

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, user1, user2] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet, user1, user2])
    })

    beforeEach('deploy GameTicket', async () => {
        ; ({ buyToken, gameToken, gameTicket, gameTicket2, gamePool, gamePoolActivity, gamePoolCS } = await loadFixTure(gamePoolsFixture));
        await buyToken.mint(wallet.address, bigNumber18.mul(10000));
        await gameToken.mint(wallet.address, bigNumber18.mul(10000));
    })

    describe('#buy', async () => {
        beforeEach('approve buyToken and gameToken to gameTicket and gameTicket2', async () => {
            await buyToken.approve(gameTicket.address, ethers.constants.MaxUint256);
            await buyToken.approve(gameTicket2.address, ethers.constants.MaxUint256);
            await gameToken.approve(gameTicket2.address, ethers.constants.MaxUint256);
        })

        it('fails for zero value', async () => {
            await expect(gameTicket.buy(BigNumber.from(0), wallet.address)).to.revertedWith("GameTicket: ZERO");
        })

        it('fails for REMAINDER', async () => {
            await expect(gameTicket.buy(bigNumber18.add(1), wallet.address)).to.revertedWith('GameTicket: REMAINDER');
        })

        it('fails for INSUFFICIENT_BALANCE', async () => {
            await expect(gameTicket.connect(user1).buy(bigNumber18, user1.address)).to.revertedWith('GameTicket: INSUFFICIENT_BALANCE');
        })

        it('success for buy', async () => {
            await gameTicket.buy(bigNumber18.mul(2), wallet.address);
            expect(await gameTicket.tickets(wallet.address)).to.eq(bigNumber18.mul(2));
            expect(await gameTicket.total()).to.eq(bigNumber18.mul(2));
        })

        it('success for buy event', async () => {
            expect(await gameTicket.buy(bigNumber18.mul(2), wallet.address)).to.emit(gameTicket, 'Bought').withArgs(wallet.address, wallet.address, bigNumber18.mul(2));
            expect(await gameTicket2.buy(bigNumber18.mul(2), wallet.address)).to.emit(gameTicket2, 'Bought').withArgs(wallet.address, wallet.address, bigNumber18.mul(2), bigNumber18.mul(20));
        })
    })


    describe('#set for GamePool', async () => {
        it('fails for diff args length', async () => {
            await expect(gamePool.setTopRate(
                [
                    BigNumber.from(1),
                    BigNumber.from(2)
                ],
                [
                    {
                        rate: BigNumber.from(100),
                        start: BigNumber.from(1),
                        end: BigNumber.from(1)
                    }
                ]
            )).to.revertedWith('invalid param')
        })

        it('fails for rate sum not 100', async () => {
            await expect(gamePool.setTopRate(
                [BigNumber.from(1)],
                [{
                    rate: BigNumber.from(99),
                    start: BigNumber.from(1),
                    end: BigNumber.from(1)
                }]
            )).to.revertedWith('sum of rate is not 100')
        })

        it('success for gamePool', async () => {
            await gamePool.setTopRate(
                [
                    BigNumber.from(1),
                    BigNumber.from(2),
                    BigNumber.from(3),
                    BigNumber.from(4),
                    BigNumber.from(5),
                    BigNumber.from(6),
                    BigNumber.from(7),
                    BigNumber.from(8)
                ],
                [
                    {
                        rate: BigNumber.from(9),
                        start: BigNumber.from(1),
                        end: BigNumber.from(1)
                    },
                    {
                        rate: BigNumber.from(8),
                        start: BigNumber.from(2),
                        end: BigNumber.from(2)
                    },
                    {
                        rate: BigNumber.from(7),
                        start: BigNumber.from(3),
                        end: BigNumber.from(3)
                    },
                    {
                        rate: BigNumber.from(6),
                        start: BigNumber.from(4),
                        end: BigNumber.from(4)
                    },
                    {
                        rate: BigNumber.from(5),
                        start: BigNumber.from(5),
                        end: BigNumber.from(5)
                    },
                    {
                        rate: BigNumber.from(15),
                        start: BigNumber.from(6),
                        end: BigNumber.from(10)
                    },
                    {
                        rate: BigNumber.from(20),
                        start: BigNumber.from(11),
                        end: BigNumber.from(20)
                    },
                    {
                        rate: BigNumber.from(30),
                        start: BigNumber.from(21),
                        end: BigNumber.from(50)
                    },
                ]
            )
            let totalTopStrategy = await gamePool.totalTopStrategy();
            expect((await gamePool.topStrategies(totalTopStrategy, 0)).rate).to.eq(BigNumber.from(0))
            expect((await gamePool.topStrategies(totalTopStrategy, 1)).rate).to.eq(BigNumber.from(9))
            expect((await gamePool.topStrategies(totalTopStrategy, 8)).rate).to.eq(BigNumber.from(30))
        })
    })

    describe('#set for GamePoolActivity', async () => {
        it('success for gamePoolActivity', async () => {
            await gamePoolActivity.setUserMaxScore(15);
            expect(await gamePoolActivity.userMaxScore()).to.eq(15);

            await gamePoolActivity.setRate({
                score: bigNumber18.mul(10),
                score1: bigNumber18.mul(1000),
                score2: bigNumber18.mul(500),
                score3: bigNumber18.mul(100)
            })
            let totalStrategy = await gamePoolActivity.totalStrategy();
            let rate = await gamePoolActivity.strategies(totalStrategy);
            expect(rate.score).to.eq(bigNumber18.mul(10));
            expect(rate.score3).to.eq(bigNumber18.mul(100));
        })
    })

    describe('#upload for GamePoolActivity', async () => {
        beforeEach('approve buyToken and gameToken to gameTicket and gameTicket2', async () => {
            await buyToken.approve(gameTicket.address, ethers.constants.MaxUint256);
            await buyToken.approve(gameTicket2.address, ethers.constants.MaxUint256);
            await gameToken.approve(gameTicket2.address, ethers.constants.MaxUint256);

        })

        it('fails for over tickets amount', async () => {
            await gamePoolActivity.setUserMaxScore(15);
            await gameTicket2.buy(bigNumber18.mul(15), wallet.address);
            await expect(gamePoolActivity.uploadOne({
                user: wallet.address,
                ticketAmount: bigNumber18.mul(18),
                score: 1,
                score1: 2,
                score2: 3,
                score3: 4
            })).to.revertedWith('ticket overflow')
        })

        it('fails for score over ticket amount', async () => {
            await gamePoolActivity.setUserMaxScore(15);
            await gameTicket2.buy(bigNumber18.mul(1), wallet.address);
            await expect(gamePoolActivity.uploadOne({
                user: wallet.address,
                ticketAmount: bigNumber18.mul(1),
                score: 1,
                score1: 2,
                score2: 3,
                score3: 4
            })).to.revertedWith('score over ticket')
        })

        it('zero for uploaded', async () => {
            let t = Math.floor(new Date().getTime()/1000) - 100;
            await expect(gamePoolActivity.uploaded(t, 0)).to.revertedWith('ticketTotal zero');
        })

        it('ok uploadOne', async () => {
            await gamePoolActivity.setUserMaxScore(15);
            await gameTicket2.buy(bigNumber18.mul(10), wallet.address);
            await gamePoolActivity.uploadOne({
                user: wallet.address,
                ticketAmount: bigNumber18.mul(10),
                score: 1,
                score1: 2,
                score2: 3,
                score3: 4
            });
            let totalRound = await gamePoolActivity.totalRound();
            expect(await gamePoolActivity.userRoundOrderMap(wallet.address, totalRound)).to.eq(BigNumber.from(0))
            expect(await gamePoolActivity.userOrders(wallet.address, BigNumber.from(0))).to.eq(BigNumber.from(0));
            let order = await gamePoolActivity.orders(BigNumber.from(0));
            expect(order.roundNumber).to.eq(BigNumber.from(0));
            expect(order.user).to.eq(wallet.address);
            expect(order.score).to.eq(1);
            expect(await gamePoolActivity.tickets(wallet.address)).to.eq(bigNumber18.mul(10));
        })

        it('invalid ticketTotal uploadOne', async () => {
            await gamePoolActivity.setUserMaxScore(15);
            await gameTicket2.buy(bigNumber18.mul(10), wallet.address);
            await gamePoolActivity.uploadOne({
                user: wallet.address,
                ticketAmount: bigNumber18.mul(10),
                score: 1,
                score1: 2,
                score2: 3,
                score3: 4
            });
            let t = Math.floor(new Date().getTime()/1000) - 100;
            await expect(gamePoolActivity.uploaded(t, bigNumber18.mul(2))).to.revertedWith('invalid ticketTotal');
        })
        it('ok uploaded', async () => {
            await gamePoolActivity.setUserMaxScore(15);
            await gameTicket2.buy(bigNumber18.mul(10), wallet.address);
            await gamePoolActivity.uploadOne({
                user: wallet.address,
                ticketAmount: bigNumber18.mul(10),
                score: 1,
                score1: 2,
                score2: 3,
                score3: 4
            });
            let t = Math.floor(new Date().getTime()/1000) - 100;
            await gamePoolActivity.uploaded(t, bigNumber18.mul(10));
        })
    })


    describe('#set for GamePoolCS', async () => {
        it('fails for diff args length', async () => {
            await expect(gamePoolCS.setTopRate(
                [
                    BigNumber.from(1),
                    BigNumber.from(2)
                ],
                [
                    {
                        rate: BigNumber.from(100),
                        start: BigNumber.from(1),
                        end: BigNumber.from(1)
                    }
                ]
            )).to.revertedWith('invalid param')
        })

        it('fails for rate sum not 100', async () => {
            await expect(gamePoolCS.setTopRate(
                [BigNumber.from(1)],
                [{
                    rate: BigNumber.from(99),
                    start: BigNumber.from(1),
                    end: BigNumber.from(1)
                }]
            )).to.revertedWith('sum of rate is not 100')
        })

        it('success for setTopRate gamePoolCS', async () => {
            await gamePoolCS.setTopRate(
                [
                    BigNumber.from(1)
                ],
                [
                    {
                        rate: BigNumber.from(100),
                        start: BigNumber.from(1),
                        end: BigNumber.from(1)
                    }
                ]
            )
            let totalTopStrategy = await gamePoolCS.totalTopStrategy();
            expect((await gamePoolCS.topStrategies(totalTopStrategy, 0)).rate).to.eq(BigNumber.from(0))
            expect((await gamePoolCS.topStrategies(totalTopStrategy, 1)).rate).to.eq(BigNumber.from(100))
        })

        it('success for setRewardSources gamePoolCS', async () => {
            await gamePoolCS.setRewardSources(
                [
                    gamePool.address
                ]
            )
            let res = await gamePoolCS.getRewardSources();
            expect(res.length).to.eq(1);

            await gamePoolCS.setRewardSources(
                [
                    gamePool.address,
                    gamePoolActivity.address
                ]
            )

            res = await gamePoolCS.getRewardSources();
            expect(res.length).to.eq(2);
            expect(res[0]).to.eq(gamePool.address);
            expect(res[1]).to.eq(gamePoolActivity.address);
        })
    })


    describe('#complete steps', async () => {
        beforeEach('setup', async () => {
            await buyToken.approve(gameTicket.address, ethers.constants.MaxUint256);
            await buyToken.approve(gameTicket2.address, ethers.constants.MaxUint256);
            await gameToken.approve(gameTicket2.address, ethers.constants.MaxUint256);

            await gameTicket.buy(bigNumber18.mul(100), wallet.address);

            await gameTicket.buyBatch([bigNumber18.mul(100),bigNumber18.mul(100)], [user1.address, user2.address]);

            await gameTicket2.buy(bigNumber18.mul(100), wallet.address);

            await gamePool.setShareAmount(bigNumber18.mul(30), bigNumber18.mul(60));
            await gamePool.setTopRate(
                [
                    BigNumber.from(1),
                    BigNumber.from(2),
                    BigNumber.from(3)
                ],
                [
                    {
                        rate: BigNumber.from(50),
                        start: BigNumber.from(1),
                        end: BigNumber.from(1)
                    },
                    {
                        rate: BigNumber.from(30),
                        start: BigNumber.from(2),
                        end: BigNumber.from(2)
                    },
                    {
                        rate: BigNumber.from(20),
                        start: BigNumber.from(3),
                        end: BigNumber.from(3)
                    }
                ]
            );

            await gamePoolActivity.setUserMaxScore(15);
            await gamePoolActivity.setRate({
                score: bigNumber18.mul(10),
                score1: bigNumber18.mul(1000),
                score2: bigNumber18.mul(500),
                score3: bigNumber18.mul(100)
            })

            await gamePoolCS.setRewardSources(
                [
                    gamePool.address,
                    gamePoolActivity.address
                ]
            )

            await gamePoolCS.setTopRate(
                [
                    BigNumber.from(1)
                ],
                [
                    {
                        rate: BigNumber.from(100),
                        start: BigNumber.from(1),
                        end: BigNumber.from(1)
                    }
                ]
            )

        })

        it('all', async () => {
            await gamePool.uploadBatch([
                {
                    user: wallet.address,
                    rank: 1,
                    ticketAmount: bigNumber18.mul(5),
                    score: 50
                },
                {
                    user: user1.address,
                    rank: 2,
                    ticketAmount: bigNumber18.mul(5),
                    score: 30
                },
                {
                    user: user2.address,
                    rank: 3,
                    ticketAmount: bigNumber18.mul(5),
                    score: 20
                }
            ]);

            await gamePool.uploaded(
                BigNumber.from(Date.now().toString()).div(1000),
                bigNumber18.mul(15),
                100,
                100,
            );

            let poolBalance = await gamePool.getBalance();
            console.log('poolBalance:', poolBalance.toString());


            await gamePoolActivity.uploadOne({
                user: wallet.address,
                ticketAmount: bigNumber18.mul(10),
                score: 1,
                score1: 2,
                score2: 3,
                score3: 4
            });
            let t = Math.floor(new Date().getTime()/1000) - 100;
            await gamePoolActivity.uploaded(t, bigNumber18.mul(10));
            
        })

        
    })
})