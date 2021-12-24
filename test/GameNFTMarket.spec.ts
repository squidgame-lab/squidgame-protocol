import { Wallet, BigNumber } from 'ethers'
import { ethers, network, waffle } from 'hardhat'
import { GameToken } from '../typechain/GameToken'
import { GameCompetitorTicket } from '../typechain/GameCompetitorTicket'
import { GameBetTicket } from '../typechain/GameBetTicket'
import { GameNFT } from '../typechain/GameNFT'
import { GameNFTMarket } from '../typechain/GameNFTMarket'
import { expect } from './shared/expect'
import { gameNFTMarketFixture, bigNumber18, bigNumber17, signRandom } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('GameNFTMarket', async () => {
    let wallet: Wallet, user1: Wallet;

    let sqt: GameToken
    let competitorTicket: GameCompetitorTicket
    let betTicket: GameBetTicket
    let hat: GameNFT
    let market: GameNFTMarket

    let loadFixTure: ReturnType<typeof createFixtureLoader>;

    before('create fixture loader', async () => {
        [wallet, user1] = await (ethers as any).getSigners()
        loadFixTure = createFixtureLoader([wallet])
    })

    beforeEach('deploy GameNFTMarket', async () => {
        ; ({ sqt, competitorTicket, betTicket, hat, market } = await loadFixTure(gameNFTMarketFixture));
        await sqt.transfer(user1.address, bigNumber18.mul(100))
        await sqt.connect(user1).approve(market.address, ethers.constants.MaxUint256)
    })

    describe('GameBetTicket', async () => {
        describe('#mint single', async () => {
            it('reverted for tokenId not in range', async () => {
                await expect(betTicket['mint(address,uint256)'](user1.address, BigNumber.from(11))).to.revertedWith("GameBetTicket: TokenId invalid")
            })

            it('reverted for repeated tokenId', async () => {
                await betTicket['mint(address,uint256)'](user1.address, BigNumber.from(5))
                await expect(betTicket['mint(address,uint256)'](user1.address, BigNumber.from(5))).to.revertedWith("ERC721: token already minted")
            })

            it('success', async () => {
                await betTicket['mint(address,uint256)'](user1.address, BigNumber.from(5))
                expect(await betTicket.ownerOf(BigNumber.from(5))).to.eq(user1.address)
            })
        })
    })

    describe('GameNFT', async () => {
        describe('#mint single', async () => {
            it('success', async () => {
                await hat['mint(address)'](user1.address)
                expect(await hat.ownerOf(BigNumber.from(1))).to.eq(user1.address)
            })
        })

        describe('#mint multi user', async () => {
            it('success', async () => {
                await hat['mint(address[])']([user1.address, user1.address])
                expect(await hat.ownerOf(BigNumber.from(1))).to.eq(user1.address)
                expect(await hat.ownerOf(BigNumber.from(2))).to.eq(user1.address)
            })
        })

        describe('#mint single user amount', async () => {
            it('success', async () => {
                await hat['mint(address,uint256)'](user1.address, BigNumber.from(2))
                expect(await hat.ownerOf(BigNumber.from(1))).to.eq(user1.address)
                expect(await hat.ownerOf(BigNumber.from(2))).to.eq(user1.address)
            })

            it('reverted for over amount', async () => {
                await hat['mint(address,uint256)'](user1.address, BigNumber.from(2))
                await hat['mint(address,uint256)'](user1.address, BigNumber.from(3))
                await expect(hat['mint(address,uint256)'](user1.address, BigNumber.from(1))).to.revertedWith("GameNFT: Invalid amount")
            })
        })
    })

    describe('GameNFTMarket', async () => {
        describe('#buy', async () => {
            it('reverted for not exist nft', async () => {
                await expect(market.buy(user1.address, BigNumber.from(1), user1.address)).to.revertedWith('GNM: Invalid nft addr')
            })

            it('reverted for nft conf rand is true', async () => {
                await expect(market.buy(betTicket.address, BigNumber.from(1), user1.address)).to.revertedWith('GNM: NFT conf is rand')
            })

            it('reverted for balance not enough', async () => {
                await expect(market.buy(hat.address, BigNumber.from(6), user1.address)).to.revertedWith('GNM: Invalid amount')
            })

            it('success', async () => {
                await market.connect(user1).buy(hat.address, BigNumber.from(2), user1.address, { value: bigNumber18.mul(2) })
                expect(await hat.ownerOf(BigNumber.from(1))).to.eq(user1.address)
                expect(await hat.ownerOf(BigNumber.from(2))).to.eq(user1.address)
            })
        })

        describe('#verify', async () => {
            it('success', async () => {
                let seeds = ["123", "124", "125"]
                let signature = await signRandom(wallet, seeds, market.address)
                expect(await market.verify(wallet.address, seeds, signature)).to.eq(true)
            })
        })

        describe('#buyRand', async () => {
            it('reverted for nft conf rand is true', async () => {
                let seeds = ["123", "124", "125"]
                let signature = await signRandom(wallet, seeds, market.address)
                await expect(market.connect(user1).buyRand(hat.address, user1.address, seeds, signature, { value: bigNumber18.mul(3) })).to.revertedWith('GNM: NFT conf is not rand')
            })

            it('success for buy three', async () => {
                let seeds = ["123", "124", "125"]
                let signature = await signRandom(wallet, seeds, market.address)
                await market.connect(user1).buyRand(betTicket.address, user1.address, seeds, signature, { value: bigNumber18.mul(3) })
                let tokenId0 = await betTicket.tokenOfOwnerByIndex(user1.address, BigNumber.from(0))
                let tokenId1 = await betTicket.tokenOfOwnerByIndex(user1.address, BigNumber.from(1))
                let tokenId2 = await betTicket.tokenOfOwnerByIndex(user1.address, BigNumber.from(2))
                expect(tokenId0).to.gte(BigNumber.from(1))
                expect(tokenId0).to.lte(BigNumber.from(10))
                expect(tokenId1).to.gte(BigNumber.from(1))
                expect(tokenId1).to.lte(BigNumber.from(10))
                expect(tokenId2).to.gte(BigNumber.from(1))
                expect(tokenId2).to.lte(BigNumber.from(10))
                expect(tokenId0).to.not.eq(tokenId1)
                expect(tokenId0).to.not.eq(tokenId2)
                expect(tokenId2).to.not.eq(tokenId1)
            })

            it('success for buy all', async () => {
                let seeds = ["121", "122", "123", "124", "125", "126", "127", "128", "129", "130"]
                let signature = await signRandom(wallet, seeds, market.address)
                await market.connect(user1).buyRand(betTicket.address, user1.address, seeds, signature, { value: bigNumber18.mul(10) })
                let balance = await betTicket.balanceOf(user1.address)
                expect(balance).to.eq(BigNumber.from(10))
                let tokenIds = []
                for (let i = 0; i < balance.toNumber(); i++) {
                    tokenIds.push((await betTicket.tokenOfOwnerByIndex(user1.address, BigNumber.from(i))).toString())
                }
                console.log('tokenIds: ', tokenIds)
            })

            it('reverted for over amount', async () => {
                let seeds = ["121", "122", "123", "124", "125", "126", "127", "128", "129", "130", "131"]
                let signature = await signRandom(wallet, seeds, market.address)
                await expect(market.connect(user1).buyRand(betTicket.address, user1.address, seeds, signature, { value: bigNumber18.mul(11) })).to.revertedWith('GNM: Invalid amount')
            })
        })

        describe('#buyLottery', async () => {
            it('success', async () => {
                let seeds = ["123", "124", "125", "126"]
                let signature = await signRandom(wallet, seeds, market.address)
                await market.connect(user1).buyLottery(competitorTicket.address, user1.address, seeds, signature)
                let balance = await competitorTicket.balanceOf(user1.address)
                let tokenIds = []
                for (let i = 0; i < balance.toNumber(); i++) {
                    tokenIds.push((await competitorTicket.tokenOfOwnerByIndex(user1.address, BigNumber.from(i))).toString())
                }
                console.log('tokenIds: ', tokenIds)
            })
        })
    })
})