import { Wallet, BigNumber } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TestToken } from '../typechain/TestToken'
import { GameTicket } from '../typechain/GameTicket'
import { GameConfig } from '../typechain/GameConfig'
import { GameToken } from '../typechain/gameToken'
import { GamePool } from '../typechain/GamePool'
import { expect } from './shared/expect'
import { gamePoolFixture, bigNumber18, bigNumber17, getBlockNumber } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GamePool', async () => {
    let wallet: Wallet, otherZero: Wallet, otherOne: Wallet;

    let buyToken: TestToken;
    let gameTicket: GameTicket;
    let gameConfig: GameConfig;
    let gameToken: GameToken
    let gamePoolDay: GamePool
    let gamePoolWeek: GamePool
    let gamePoolMonth: GamePool

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, otherZero, otherOne] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet, otherZero, otherOne])
    })

    beforeEach('mock players', async () => {
        ; ({ buyToken, gameTicket, gameConfig, gameToken, gamePoolDay, gamePoolWeek, gamePoolMonth } = await loadFixTure(gamePoolFixture));
        await buyToken.mint(wallet.address, bigNumber18.mul(10000));

        await buyToken.approve(gameTicket.address, ethers.constants.MaxUint256);
        await gameTicket.buy(bigNumber18.mul(10), wallet.address);

        await buyToken.transfer(otherZero.address, bigNumber18.mul(100))
        await buyToken.connect(otherZero).approve(gameTicket.address, ethers.constants.MaxUint256);
        await gameTicket.connect(otherZero).buy(bigNumber18.mul(10), otherZero.address);

        await buyToken.transfer(otherOne.address, bigNumber18.mul(100))
        await buyToken.connect(otherOne).approve(gameTicket.address, ethers.constants.MaxUint256);
        await gameTicket.connect(otherOne).buy(bigNumber18.mul(10), otherOne.address);
    })

    describe('#setTopRate', async () => {
        it('fails for diff args length', async () => {
            await expect(gamePoolDay.setTopRate(
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
            await expect(gamePoolDay.setTopRate(
                [BigNumber.from(1)],
                [{
                    rate: BigNumber.from(99),
                    start: BigNumber.from(1),
                    end: BigNumber.from(1)
                }]
            )).to.revertedWith('sum of rate is not 100')
        })

        it('success', async () => {
            await gamePoolDay.setTopRate(
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
            let totalTopStrategy = await gamePoolDay.totalTopStrategy();
            expect((await gamePoolDay.topStrategies(totalTopStrategy, 0)).rate).to.eq(BigNumber.from(0))
            expect((await gamePoolDay.topStrategies(totalTopStrategy, 1)).rate).to.eq(BigNumber.from(9))
            expect((await gamePoolDay.topStrategies(totalTopStrategy, 8)).rate).to.eq(BigNumber.from(30))
        })
    })

    describe('#uploadOne', async () => {
        beforeEach('mock set', async () => {
            await mockSet();
        })

        it('fails for caller not manager', async () => {
            await expect(gamePoolDay.connect(otherZero).uploadOne({
                user: wallet.address,
                rank: 1,
                ticketAmount: bigNumber18.mul(5),
                score: 50
            })).to.reverted
        })

        it('fails for over tickets amount', async () => {
            await expect(gamePoolDay.uploadOne({
                user: wallet.address,
                rank: 1,
                ticketAmount: bigNumber18.mul(15),
                score: 50
            })).to.revertedWith('ticket overflow')
        })

        it('zero user address', async () => {
            await gamePoolDay.uploadOne({
                user: ethers.constants.AddressZero,
                rank: 1,
                ticketAmount: bigNumber18.mul(0),
                score: 50
            })
            let order = await gamePoolDay.orders(BigNumber.from(0));
            expect(order[0]).to.eq(BigNumber.from(0));
            expect(order[1]).to.eq(ethers.constants.AddressZero);
        })

        it('success for case one person upload once', async () => {
            await gamePoolDay.uploadOne({
                user: wallet.address,
                rank: 1,
                ticketAmount: bigNumber18.mul(5),
                score: 50
            })
            let totalRound = await gamePoolDay.totalRound();
            expect(await gamePoolDay.userRoundOrderMap(wallet.address, totalRound)).to.eq(BigNumber.from(0))
            expect(await gamePoolDay.userOrders(wallet.address, BigNumber.from(0))).to.eq(BigNumber.from(0));
            // expect(await gamePoolDay.roundOrders(totalRound, BigNumber.from(0))).to.eq(BigNumber.from(0));
            let order = await gamePoolDay.orders(BigNumber.from(0));
            expect(order.roundNumber).to.eq(BigNumber.from(0));
            expect(order.user).to.eq(wallet.address);
            expect(await gamePoolDay.tickets(wallet.address)).to.eq(bigNumber18.mul(5));
        })

        it('success for case one person upload twice', async () => {
            await gamePoolDay.uploadOne({
                user: wallet.address,
                rank: 1,
                ticketAmount: bigNumber18.mul(5),
                score: 50
            })
            await gamePoolDay.uploadOne({
                user: wallet.address,
                rank: 2,
                ticketAmount: bigNumber18.mul(5),
                score: 50
            })
            let totalRound = await gamePoolDay.totalRound();
            expect(await gamePoolDay.userRoundOrderMap(wallet.address, totalRound)).to.eq(BigNumber.from(0))
            expect(await gamePoolDay.userOrders(wallet.address, BigNumber.from(0))).to.eq(BigNumber.from(0));
            // expect(await gamePoolDay.roundOrders(totalRound, BigNumber.from(0))).to.eq(BigNumber.from(0));
            let order = await gamePoolDay.orders(BigNumber.from(0));
            expect(order.roundNumber).to.eq(BigNumber.from(0));
            expect(order.user).to.eq(wallet.address);
            expect(order.rank).to.eq(2)
            expect(await gamePoolDay.tickets(wallet.address)).to.eq(bigNumber18.mul(5));
        })

        it('gas', async () => {
            let tx = await gamePoolDay.uploadOne({
                user: wallet.address,
                rank: 1,
                ticketAmount: bigNumber18.mul(5),
                score: 50
            })
            let receipt = await tx.wait();
            expect(receipt.gasUsed).to.eq(212616);
        })
    })

    describe('#uploadBatch', async () => {
        beforeEach('mock set', async () => {
            await mockSet();
        })

        beforeEach('buy tickets', async () => {
            await buyToken.approve(gameTicket.address, ethers.constants.MaxUint256);
            await gameTicket.buy(bigNumber18.mul(10), wallet.address);

            await buyToken.transfer(otherZero.address, bigNumber18.mul(100))
            await buyToken.connect(otherZero).approve(gameTicket.address, ethers.constants.MaxUint256);
            await gameTicket.connect(otherZero).buy(bigNumber18.mul(10), otherZero.address);

            await buyToken.transfer(otherOne.address, bigNumber18.mul(100))
            await buyToken.connect(otherOne).approve(gameTicket.address, ethers.constants.MaxUint256);
            await gameTicket.connect(otherOne).buy(bigNumber18.mul(10), otherOne.address);
        })

        it('fails for caller not manager', async () => {
            await expect(gamePoolDay.connect(otherZero).uploadBatch([{
                user: wallet.address,
                rank: 1,
                ticketAmount: bigNumber18.mul(5),
                score: 50
            }])).to.reverted
        })

        it('success', async () => {
            await gamePoolDay.uploadBatch([
                {
                    user: wallet.address,
                    rank: 1,
                    ticketAmount: bigNumber18.mul(5),
                    score: 50
                },
                {
                    user: otherZero.address,
                    rank: 2,
                    ticketAmount: bigNumber18.mul(5),
                    score: 30
                },
                {
                    user: otherOne.address,
                    rank: 3,
                    ticketAmount: bigNumber18.mul(5),
                    score: 20
                }
            ])
            // let totalRound = await gamePoolDay.totalRound();
            expect(await gamePoolDay.userOrders(wallet.address, 0)).to.eq(0);
            expect(await gamePoolDay.userOrders(otherZero.address, 0)).to.eq(1);
            expect(await gamePoolDay.userOrders(otherOne.address, 0)).to.eq(2);
        })

        it('gas', async () => {
            let tx = await gamePoolDay.uploadBatch([
                {
                    user: wallet.address,
                    rank: 1,
                    ticketAmount: bigNumber18.mul(5),
                    score: 50
                },
                {
                    user: otherZero.address,
                    rank: 2,
                    ticketAmount: bigNumber18.mul(5),
                    score: 30
                },
                {
                    user: otherOne.address,
                    rank: 3,
                    ticketAmount: bigNumber18.mul(5),
                    score: 20
                }
            ])
            let receipt = await tx.wait();
            expect(receipt.gasUsed).to.eq(503951)
        })
    })

    describe('#uploaded', async () => {
        beforeEach('upload results', async () => {
            await mockSet();
            await mockUpload();
        })

        it('fails for zero ticketTotal', async () => {
            await expect(gamePoolDay.uploaded(BigNumber.from(0), BigNumber.from(0), bigNumber18, bigNumber18)).to.revertedWith('ticketTotal zero');
        })

        it('fails for invalid ticketTotal', async () => {
            await expect(gamePoolDay.uploaded(BigNumber.from(Date.now().toString()).div(1000).add(86400), bigNumber18, bigNumber18, bigNumber18)).to.revertedWith('invalid ticketTotal');
        })

        it('success', async () => {
            // gamePoolDay
            await gamePoolDay.uploaded(
                BigNumber.from(Date.now().toString()).div(1000),
                bigNumber18.mul(15),
                100,
                100,
            );
            expect(await gamePoolDay.totalRound()).to.eq(1);
            expect(await buyToken.balanceOf(gamePoolDay.address)).to.eq(bigNumber18.mul(15));
            expect(await gamePoolDay.nextPoolTotal()).to.eq(bigNumber18.mul(3))
            // gamePoolWeek
            await gamePoolWeek.uploaded(
                BigNumber.from(Date.now().toString()).div(1000),
                bigNumber18.mul(15),
                100,
                100,
            );
            expect(await gamePoolDay.nextPoolTotal()).to.eq(0);
            expect(await gamePoolWeek.totalRound()).to.eq(1);
            expect(await buyToken.balanceOf(gamePoolDay.address)).to.eq(bigNumber18.mul(12));
            expect(await buyToken.balanceOf(gamePoolWeek.address)).to.eq(bigNumber18.mul(3));
            expect(await gamePoolWeek.nextPoolTotal()).to.eq(bigNumber17.mul(6))
            // gamePoolMonth
            await gamePoolMonth.uploaded(
                BigNumber.from(Date.now().toString()).div(1000),
                bigNumber18.mul(15),
                100,
                100,
            );
            expect(await gamePoolWeek.nextPoolTotal()).to.eq(0);
            expect(await gamePoolMonth.totalRound()).to.eq(1);
            expect(await buyToken.balanceOf(gamePoolWeek.address)).to.eq(bigNumber17.mul(24));
            expect(await buyToken.balanceOf(gamePoolMonth.address)).to.eq(bigNumber17.mul(6));
            expect(await gamePoolMonth.nextPoolTotal()).to.eq(0)
        })

        it('gas', async () => {
            let tx = await gamePoolDay.uploaded(
                BigNumber.from(Date.now().toString()).div(1000),
                bigNumber18.mul(15),
                100,
                100,
            );
            let receipt = await tx.wait();
            expect(receipt.gasUsed).to.eq(221208)
        })
    })

    describe('#getOrderResult', async () => {
        beforeEach('mock uploaded', async () => {
            await getBlockNumber();
            await mockSet();
            await mockUpload();
            await mockUploaded();
        })

        it('success', async () => {
            await getBlockNumber();
            let orderResult0 = await gamePoolDay.getOrderResult(0);
            let orderResult1 = await gamePoolDay.getOrderResult(1);
            let orderResult2 = await gamePoolDay.getOrderResult(2);
            // orderId
            expect(orderResult0.orderId).to.eq(0)
            expect(orderResult1.orderId).to.eq(1)
            expect(orderResult2.orderId).to.eq(2)
            // roundNumber
            expect(orderResult0.roundNumber).to.eq(0)
            expect(orderResult1.roundNumber).to.eq(0)
            expect(orderResult2.roundNumber).to.eq(0)
            // user
            expect(orderResult0.user).to.eq(wallet.address)
            expect(orderResult1.user).to.eq(otherZero.address)
            expect(orderResult2.user).to.eq(otherOne.address)
            // rank
            expect(orderResult0.rank).to.eq(1)
            expect(orderResult1.rank).to.eq(2)
            expect(orderResult2.rank).to.eq(3)
            // ticketAmount
            expect(orderResult0.ticketAmount).to.eq(bigNumber18.mul(5))
            expect(orderResult1.ticketAmount).to.eq(bigNumber18.mul(5))
            expect(orderResult2.ticketAmount).to.eq(bigNumber18.mul(5))
            // score
            expect(orderResult0.score).to.eq(BigNumber.from(50))
            expect(orderResult1.score).to.eq(BigNumber.from(30))
            expect(orderResult2.score).to.eq(BigNumber.from(20))
            // claimedWin
            expect(orderResult0.claimedWin).to.eq(0)
            expect(orderResult1.claimedWin).to.eq(0)
            expect(orderResult2.claimedWin).to.eq(0)
            // claimedShareParticipationAmount
            expect(orderResult0.claimedShareParticipationAmount).to.eq(0)
            expect(orderResult1.claimedShareParticipationAmount).to.eq(0)
            expect(orderResult2.claimedShareParticipationAmount).to.eq(0)
            // claimedShareTopAmount
            expect(orderResult0.claimedShareTopAmount).to.eq(0)
            expect(orderResult1.claimedShareTopAmount).to.eq(0)
            expect(orderResult2.claimedShareTopAmount).to.eq(0)
            // claimWin
            expect(orderResult0.claimWin).to.eq(bigNumber18.mul(6))
            expect(orderResult1.claimWin).to.eq(bigNumber17.mul(36))
            expect(orderResult2.claimWin).to.eq(bigNumber17.mul(24))
            // claimShareParticipationAmount
            expect(orderResult0.claimShareParticipationAmount).to.eq(bigNumber18.mul(10))
            expect(orderResult1.claimShareParticipationAmount).to.eq(bigNumber18.mul(10))
            expect(orderResult2.claimShareParticipationAmount).to.eq(bigNumber18.mul(10))
            // claimShareTopAmount
            expect(orderResult0.claimShareTopAmount).to.eq(bigNumber18.mul(30))
            expect(orderResult1.claimShareTopAmount).to.eq(bigNumber18.mul(18))
            expect(orderResult2.claimShareTopAmount).to.eq(bigNumber18.mul(12))
            // claimShareTopAvaliable
            await getBlockNumber();
            await new Promise(f => setTimeout(f, 1000));
            expect(orderResult0.claimShareTopAvaliable).to.eq(bigNumber18.mul(30));
            expect(orderResult1.claimShareTopAvaliable).to.eq(bigNumber18.mul(18));
            expect(orderResult2.claimShareTopAvaliable).to.eq(bigNumber18.mul(12));
            await getBlockNumber();
        })
    })

    describe('#caim', async () => {
        beforeEach('mock uploaded', async () => {
            await mockSet();
            await mockUpload();
            await mockUploaded();
        })

        it('fails for not exist orderId', async () => {
            await expect(gamePoolDay.claim(3)).to.reverted;
        })

        it('fails for caller not order user', async () => {
            await expect(gamePoolDay.claim(1)).to.revertedWith('forbidden');
        })

        it('success for claim order0', async () => {
            let ticketBalanceBefore = await buyToken.balanceOf(wallet.address);
            let shareBalanceBefore = await gameToken.balanceOf(wallet.address);
            await new Promise(f => setTimeout(f, 1000));
            await gamePoolDay.claim(0);
            let ticketBalanceAfter = await buyToken.balanceOf(wallet.address);
            let shareBalanceAfter = await gameToken.balanceOf(wallet.address);
            expect(ticketBalanceAfter.sub(ticketBalanceBefore)).to.eq(bigNumber18.mul(6));
            expect(shareBalanceAfter.sub(shareBalanceBefore)).to.eq(bigNumber18.mul(40));
            let orderResult0 = await gamePoolDay.getOrderResult(0);
            expect(orderResult0.claimedWin).to.eq(bigNumber18.mul(6))
            expect(orderResult0.claimedShareParticipationAmount).to.eq(bigNumber18.mul(10))
            expect(orderResult0.claimedShareTopAmount).to.eq(bigNumber18.mul(30))
            expect(orderResult0.claimShareTopAvaliable).to.eq(0);
        })

        it('success for claim twice', async () => {
            await new Promise(f => setTimeout(f, 1000));
            await gamePoolDay.claim(0);
            let ticketBalanceBefore = await buyToken.balanceOf(wallet.address);
            let shareBalanceBefore = await gameToken.balanceOf(wallet.address);
            await gamePoolDay.claim(0);
            let ticketBalanceAfter = await buyToken.balanceOf(wallet.address);
            let shareBalanceAfter = await gameToken.balanceOf(wallet.address);
            expect(ticketBalanceAfter).to.eq(ticketBalanceBefore);
            expect(shareBalanceAfter).to.eq(shareBalanceBefore);
        })

        it('success for claim order0 in gamePoolWeek', async () => {
            await new Promise(f => setTimeout(f, 1000));
            await gamePoolDay.claim(0);
            let ticketBalanceBefore = await buyToken.balanceOf(wallet.address);
            let shareBalanceBefore = await gameToken.balanceOf(wallet.address);
            await new Promise(f => setTimeout(f, 1000));
            await gamePoolWeek.claim(0);
            let ticketBalanceAfter = await buyToken.balanceOf(wallet.address);
            let shareBalanceAfter = await gameToken.balanceOf(wallet.address);
            expect(ticketBalanceAfter.sub(ticketBalanceBefore)).to.eq(bigNumber17.mul(12));
            expect(shareBalanceAfter.sub(shareBalanceBefore)).to.eq(bigNumber18.mul(80));
        })

        it('success for claim order0 in gamePoolMonth', async () => {
            await new Promise(f => setTimeout(f, 1000));
            await gamePoolDay.claim(0);
            await new Promise(f => setTimeout(f, 1000));
            await gamePoolWeek.claim(0);
            let ticketBalanceBefore = await buyToken.balanceOf(wallet.address);
            let shareBalanceBefore = await gameToken.balanceOf(wallet.address);
            await new Promise(f => setTimeout(f, 1000));
            await gamePoolMonth.claim(0);
            let ticketBalanceAfter = await buyToken.balanceOf(wallet.address);
            let shareBalanceAfter = await gameToken.balanceOf(wallet.address);
            expect(ticketBalanceAfter.sub(ticketBalanceBefore)).to.eq(bigNumber17.mul(3));
            expect(shareBalanceAfter.sub(shareBalanceBefore)).to.eq(bigNumber18.mul(160));
        })

        it('success for claim order0', async () => {
            await new Promise(f => setTimeout(f, 1000));
            let tx = await gamePoolDay.claim(0);
            let receipt = await tx.wait();
            expect(receipt.gasUsed).to.eq(211075);
        })
    })

    describe('#uploaded&&cliam', async () => {
        beforeEach('mock set and upload', async () => {
            await mockSet();
            await mockUpload();
        })

        it('success', async () => {
            // gamePoolDay
            await gamePoolDay.uploaded(
                BigNumber.from(Date.now().toString()).div(1000),
                bigNumber18.mul(15),
                100,
                100,
            );
            expect(await buyToken.balanceOf(gamePoolDay.address)).to.eq(bigNumber18.mul(15));
            expect(await gamePoolDay.nextPoolTotal()).to.eq(bigNumber18.mul(3))
            await gamePoolDay.claim(0);
            // gamePoolWeek
            await gamePoolWeek.uploaded(
                BigNumber.from(Date.now().toString()).div(1000),
                bigNumber18.mul(15),
                100,
                100,
            );
            expect(await gamePoolDay.nextPoolTotal()).to.eq(0);
            expect(await buyToken.balanceOf(gamePoolWeek.address)).to.eq(bigNumber18.mul(3));
            expect(await gamePoolWeek.nextPoolTotal()).to.eq(bigNumber17.mul(6))
            await gamePoolWeek.claim(0)
            // gamePoolMonth
            await gamePoolMonth.uploaded(
                BigNumber.from(Date.now().toString()).div(1000),
                bigNumber18.mul(15),
                100,
                100,
            );
            expect(await gamePoolWeek.nextPoolTotal()).to.eq(0);
            expect(await buyToken.balanceOf(gamePoolMonth.address)).to.eq(bigNumber17.mul(6));
            expect(await gamePoolMonth.nextPoolTotal()).to.eq(0)

        })
    })

    describe('#claimAll', async () => {
        beforeEach('mock set', async () => {
            await mockSet();

            await buyToken.approve(gameTicket.address, ethers.constants.MaxUint256);
            await gameTicket.buy(bigNumber18.mul(20), wallet.address);

            await buyToken.transfer(otherZero.address, bigNumber18.mul(100))
            await buyToken.connect(otherZero).approve(gameTicket.address, ethers.constants.MaxUint256);
            await gameTicket.connect(otherZero).buy(bigNumber18.mul(20), otherZero.address);

            await buyToken.transfer(otherOne.address, bigNumber18.mul(100))
            await buyToken.connect(otherOne).approve(gameTicket.address, ethers.constants.MaxUint256);
            await gameTicket.connect(otherOne).buy(bigNumber18.mul(20), otherOne.address);
        })


        it('success', async () => {
            await gamePoolDay.setFeeRate(1000);
            await gamePoolDay.uploadBatch([
                {
                    user: wallet.address,
                    rank: 1,
                    ticketAmount: bigNumber18.mul(5),
                    score: 50
                },
                {
                    user: otherZero.address,
                    rank: 2,
                    ticketAmount: bigNumber18.mul(5),
                    score: 30
                },
                {
                    user: otherOne.address,
                    rank: 3,
                    ticketAmount: bigNumber18.mul(5),
                    score: 20
                }
            ])
            // let totalRound = await gamePoolDay.totalRound();
            expect(await gamePoolDay.userOrders(wallet.address, 0)).to.eq(0);
            expect(await gamePoolDay.userOrders(otherZero.address, 0)).to.eq(1);
            expect(await gamePoolDay.userOrders(otherOne.address, 0)).to.eq(2);

            await gamePoolDay.uploaded(
                BigNumber.from(Date.now().toString()).div(1000),
                bigNumber18.mul(15),
                100,
                100,
            );

            await new Promise(f => setTimeout(f, 1000));
            let tx = await gamePoolDay.uploadBatch([
                {
                    user: wallet.address,
                    rank: 1,
                    ticketAmount: bigNumber18.mul(10),
                    score: 50
                },
                {
                    user: otherZero.address,
                    rank: 2,
                    ticketAmount: bigNumber18.mul(10),
                    score: 30
                },
                {
                    user: otherOne.address,
                    rank: 3,
                    ticketAmount: bigNumber18.mul(10),
                    score: 20
                }
            ])


            await gamePoolDay.uploaded(
                BigNumber.from(Date.now().toString()).div(1000),
                bigNumber18.mul(30),
                100,
                100,
            );

            let beforeBalance = await buyToken.balanceOf(otherOne.address);
            let beforeShareBalance = await gameToken.balanceOf(otherOne.address);

            let orders = await gamePoolDay.iterateReverseUserOrders(otherOne.address, 10, 0);
            let data:any = [];
            let claimValue = BigNumber.from(0);
            let claimShareValue = BigNumber.from(0);
            for(let o of orders) {
                let d:any = {...o};
                claimValue = claimValue.add(d.claimWin);
                claimShareValue = claimShareValue.add(d.claimShareParticipationAmount).add(d.claimShareTopAmount);
                d.orderId = d.orderId.toString();
                d.roundNumber = d.roundNumber.toString();
                d.claimWin = d.claimWin.toString();
                d.claimShareParticipationAmount = d.claimShareParticipationAmount.toString();
                d.claimShareTopAmount = d.claimShareTopAmount.toString();
                data.push(d);
            }
            console.log('orders:', data);

            await new Promise(f => setTimeout(f, 1000));
            await gamePoolDay.connect(otherOne).claimAll(0, 10);
            let afterBalance = await buyToken.balanceOf(otherOne.address);
            let afterShareBalance = await gameToken.balanceOf(otherOne.address);
            console.log('beforeBalance:', beforeBalance.toString(), 'afterBalance:', afterBalance.toString(), 'claimValue:', claimValue.toString(), 'claimed', afterBalance.sub(beforeBalance).toString());
            console.log('beforeShareBalance:', beforeShareBalance.toString(), 'afterShareBalance:', afterShareBalance.toString(), 'claimShareValue:', claimShareValue.toString(), 'claimed', afterShareBalance.sub(beforeShareBalance).toString());
            expect(afterBalance.sub(beforeBalance)).to.eq(claimValue.mul(9).div(10));
            expect(afterShareBalance.sub(beforeShareBalance)).to.eq(claimShareValue);
        })
    })

    async function mockSet() {
        // gamePoolDay
        await gamePoolDay.setShareAmount(bigNumber18.mul(30), bigNumber18.mul(60));
        await gamePoolDay.setTopRate(
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
        // gamePoolWeek
        await gamePoolWeek.setShareAmount(bigNumber18.mul(60), bigNumber18.mul(120));
        await gamePoolWeek.setTopRate(
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
        // gamePoolMonth
        await gamePoolMonth.setShareAmount(bigNumber18.mul(120), bigNumber18.mul(240));
        await gamePoolMonth.setTopRate(
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
    }

    async function mockUpload() {
        // gamePoolDay
        await gamePoolDay.uploadBatch([
            {
                user: wallet.address,
                rank: 1,
                ticketAmount: bigNumber18.mul(5),
                score: 50
            },
            {
                user: otherZero.address,
                rank: 2,
                ticketAmount: bigNumber18.mul(5),
                score: 30
            },
            {
                user: otherOne.address,
                rank: 3,
                ticketAmount: bigNumber18.mul(5),
                score: 20
            }
        ]);
        // gamePoolWeek
        await gamePoolWeek.uploadBatch([
            {
                user: wallet.address,
                rank: 1,
                ticketAmount: bigNumber18.mul(5),
                score: 50
            },
            {
                user: otherZero.address,
                rank: 2,
                ticketAmount: bigNumber18.mul(5),
                score: 30
            },
            {
                user: otherOne.address,
                rank: 3,
                ticketAmount: bigNumber18.mul(5),
                score: 20
            }
        ]);
        // gamePoolMonth
        await gamePoolMonth.uploadBatch([
            {
                user: wallet.address,
                rank: 1,
                ticketAmount: bigNumber18.mul(5),
                score: 50
            },
            {
                user: otherZero.address,
                rank: 2,
                ticketAmount: bigNumber18.mul(5),
                score: 30
            },
            {
                user: otherOne.address,
                rank: 3,
                ticketAmount: bigNumber18.mul(5),
                score: 20
            }
        ]);
    }

    async function mockUploaded() {
        // gamePoolDay
        await gamePoolDay.uploaded(
            BigNumber.from(Date.now().toString()).div(1000),
            bigNumber18.mul(15),
            100,
            100,
        );
        // gamePoolWeek
        await gamePoolWeek.uploaded(
            BigNumber.from(Date.now().toString()).div(1000),
            bigNumber18.mul(15),
            100,
            100,
        );
        // gamePoolMonth
        await gamePoolMonth.uploaded(
            BigNumber.from(Date.now().toString()).div(1000),
            bigNumber18.mul(15),
            100,
            100,
        );
    }
})