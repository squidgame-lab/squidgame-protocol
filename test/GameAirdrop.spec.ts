import { Wallet, BigNumber } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { GameToken } from '../typechain/GameToken'
import { GameAirdrop } from '../typechain/GameAirdrop'
import { expect } from './shared/expect'
import { gameAirdropFixture, bigNumber18, dateNow } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GameAirdrop', async () => {
    let wallet: Wallet,
        user1: Wallet,
        user2: Wallet,
        user3: Wallet,
        user4: Wallet,
        user5: Wallet;

    let gameToken: GameToken;
    let gameAirdrop: GameAirdrop;

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, user1, user2, user3, user4, user5] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader()
    })

    beforeEach('deploy GameAirdrop', async () => {
        ; ({ gameToken, gameAirdrop } = await loadFixTure(gameAirdropFixture));
    })

    it('check airdrop info', async () => {
        expect(await gameAirdrop.token()).to.eq(gameToken.address)
        expect(await gameAirdrop.total()).to.eq(bigNumber18.mul(100))
        expect(await gameAirdrop.balance()).to.eq(bigNumber18.mul(100))
        expect(await gameAirdrop.startTime()).to.eq(dateNow)
        expect(await gameAirdrop.endTime()).to.eq(dateNow.add(86400))
    })

    describe('#batchSetAllowanceList', async () => {
        it('false for wrong args length', async () => {
            await expect(gameAirdrop.batchSetAllowanceList(
                [user1.address, user2.address],
                [bigNumber18.mul(60), bigNumber18.mul(40), bigNumber18.mul(40)]
            )).to.revertedWith('GameAirdrop: INVALID_PARAMS')
        })

        it('success', async () => {
            await gameAirdrop.batchSetAllowanceList(
                [user1.address, user2.address],
                [bigNumber18.mul(60), bigNumber18.mul(40)]
            )
            expect(await gameAirdrop.allowanceList(user1.address)).to.eq(bigNumber18.mul(60))
            expect(await gameAirdrop.allowanceList(user2.address)).to.eq(bigNumber18.mul(40))
        })

        it('gas used for two', async () => {
            let tx = await gameAirdrop.batchSetAllowanceList(
                [user1.address, user2.address],
                [bigNumber18.mul(60), bigNumber18.mul(40)]
            )
            let reiceipt = await tx.wait()
            expect(reiceipt.gasUsed).to.eq(73276)
        })

        it('gas used for five', async () => {
            let tx = await gameAirdrop.batchSetAllowanceList(
                [
                    user1.address,
                    user2.address,
                    user3.address,
                    user4.address,
                    user5.address
                ],
                [
                    bigNumber18.mul(20),
                    bigNumber18.mul(20),
                    bigNumber18.mul(20),
                    bigNumber18.mul(20),
                    bigNumber18.mul(20)
                ]
            )
            let reiceipt = await tx.wait()
            expect(reiceipt.gasUsed).to.eq(143248)
        })
    })

    describe('#batchSetAllowanceListSame', async () => {
        it('gas used for two', async () => {
            let tx = await gameAirdrop.batchSetAllowanceListSame(
                [user1.address, user2.address],
                bigNumber18.mul(50)
            )
            let reiceipt = await tx.wait()
            expect(reiceipt.gasUsed).to.eq(72473)
        })

        it('gas used for five', async () => {
            let tx = await gameAirdrop.batchSetAllowanceListSame(
                [
                    user1.address,
                    user2.address,
                    user3.address,
                    user4.address,
                    user5.address
                ],
                bigNumber18.mul(20)
            )
            let reiceipt = await tx.wait()
            expect(reiceipt.gasUsed).to.eq(141665)
        })
    })

    describe('#claim', async () => {
        beforeEach('set allowance list', async () => {
            await gameAirdrop.batchSetAllowanceList(
                [user1.address, user2.address],
                [bigNumber18.mul(60), bigNumber18.mul(40)]
            )
        })

        it('success', async () => {
            let balanceBefore = await gameToken.balanceOf(user1.address);
            await gameAirdrop.connect(user1).claim();
            let balanceAfter = await gameToken.balanceOf(user1.address);
            expect(balanceAfter.sub(balanceBefore)).to.eq(bigNumber18.mul(60));
            expect(await gameAirdrop.balance()).to.eq(bigNumber18.mul(40));
            expect(await gameAirdrop.claimed(user1.address)).to.eq(true);
            expect(await gameAirdrop.claimedCount()).to.eq(1);
        })

        it('fails for duplication claim', async () => {
            await gameAirdrop.connect(user1).claim();
            await expect(gameAirdrop.connect(user1).claim()).to.revertedWith('GameAirdrop: DUPLICATION_CLAIM');
        })

        it('success for over amount', async () => {
            await gameAirdrop.setAllowanceList(user1.address, bigNumber18.mul(110));
            let balanceBefore = await gameToken.balanceOf(user1.address);
            await gameAirdrop.connect(user1).claim();
            let balanceAfter = await gameToken.balanceOf(user1.address);
            expect(balanceAfter.sub(balanceBefore)).to.eq(bigNumber18.mul(100));
            expect(await gameAirdrop.balance()).to.eq(BigNumber.from(0));
        })

        it('fails for insufficient balance', async () => {
            await gameAirdrop.setAllowanceList(user1.address, bigNumber18.mul(110));
            await gameAirdrop.connect(user1).claim();
            await expect(gameAirdrop.connect(user2).claim()).to.revertedWith('GameAirdrop: INSUFFICIENT_BALANCE');
        })
    })
})