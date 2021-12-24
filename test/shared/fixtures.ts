import { BigNumber, Wallet } from 'ethers'
import { ethers, network } from 'hardhat'
import { TestToken } from '../../typechain/TestToken'
import { GameTicket } from '../../typechain/GameTicket'
import { GameTicket2 } from '../../typechain/GameTicket2'
import { GameConfig } from '../../typechain/GameConfig'
import { GamePool } from '../../typechain/GamePool'
import { GamePoolActivity } from '../../typechain/GamePoolActivity'
import { GamePoolCS } from '../../typechain/GamePoolCS'
import { GameToken } from '../../typechain/GameToken'
import { GameAirdrop } from '../../typechain/GameAirdrop'
import { GameTimeLock } from '../../typechain/GameTimeLock'
import { GameSchedualPool } from '../../typechain/GameSchedualPool'
import { GameSinglePool } from '../../typechain/GameSinglePool'
import { GameFarm } from '../../typechain/GameFarm'
import { WETH9 } from '../../typechain/WETH9'
import { MockGameTicket } from '../../typechain/MockGameTicket'
import { PancakeFactory } from '../../typechain/PancakeFactory'
import { PancakeRouter } from '../../typechain/PancakeRouter'
import { GameTicketExchange } from '../../typechain/GameTicketExchange'
import { GamePrediction } from '../../typechain/GamePrediction'
import { GameNFTMarket } from '../../typechain/GameNFTMarket'
import { GameCompetitorTicket } from '../../typechain/GameCompetitorTicket'
import { GameBetTicket } from '../../typechain/GameBetTicket'
import { GameNFT } from '../../typechain/GameNFT'
import { Fixture, deployMockContract, MockContract } from 'ethereum-waffle'
import { abi as TimeLockABI } from '../../artifacts/contracts/interfaces/IGameTimeLock.sol/IGameTimeLock.json'
export const bigNumber18 = BigNumber.from("1000000000000000000")  // 1e18
export const bigNumber17 = BigNumber.from("100000000000000000")  //1e17
export const dateNow = BigNumber.from("1636429275") // 2021-11-09 11:41:15
export const deadline = BigNumber.from('1893427200') // 2030

export async function getBlockNumber() {
    const blockNumber = await ethers.provider.getBlockNumber()
    console.debug("Current block number: " + blockNumber);
    return blockNumber;
}

interface TestTokensFixture {
    buyToken: TestToken
}

async function testTokensFixture(): Promise<TestTokensFixture> {
    let testTokenFactory = await ethers.getContractFactory('TestToken')
    let buyToken = (await testTokenFactory.deploy()) as TestToken
    await buyToken.initialize();
    return { buyToken }
}


interface GameTicketFixture extends TestTokensFixture {
    gameTicket: GameTicket
    gameConfig: GameConfig
}

export const gameTicketFixture: Fixture<GameTicketFixture> = async function (): Promise<GameTicketFixture> {
    return await _gameTicketFixture();
}

async function _gameTicketFixture(): Promise<GameTicketFixture> {
    const { buyToken } = await testTokensFixture();

    const gameConfigFactory = await ethers.getContractFactory('GameConfig');
    const gameTicketFactory = await ethers.getContractFactory('GameTicket');

    const gameConfig = (await gameConfigFactory.deploy()) as GameConfig;
    await gameConfig.initialize();

    const gameTicket = (await gameTicketFactory.deploy()) as GameTicket;
    await gameTicket.initialize(buyToken.address, bigNumber18);
    await gameTicket.setupConfig(gameConfig.address);

    return { buyToken, gameTicket, gameConfig };
}


interface GamePoolFixture extends GameTicketFixture {
    gameToken: GameToken
    gamePoolDay: GamePool
    gamePoolWeek: GamePool
    gamePoolMonth: GamePool
}

export const gamePoolFixture: Fixture<GamePoolFixture> = async function (): Promise<GamePoolFixture> {
    const { buyToken, gameTicket, gameConfig } = await _gameTicketFixture();

    const gameTokenFactory = await ethers.getContractFactory('GameToken');
    const gamePoolFactory = await ethers.getContractFactory('GamePool');

    const gameToken = (await gameTokenFactory.deploy()) as GameToken;
    await gameToken.initialize();
    const gamePoolDay = (await gamePoolFactory.deploy()) as GamePool;
    await gamePoolDay.initialize();
    const gamePoolWeek = (await gamePoolFactory.deploy()) as GamePool;
    await gamePoolWeek.initialize()
    const gamePoolMonth = (await gamePoolFactory.deploy()) as GamePool;
    await gamePoolMonth.initialize()

    await gameToken.increaseFunds([gamePoolDay.address, gamePoolWeek.address, gamePoolMonth.address], [ethers.constants.MaxUint256, ethers.constants.MaxUint256, ethers.constants.MaxUint256])
    await gamePoolDay.configure(
        gameTicket.address,
        gameToken.address,
        gamePoolWeek.address,
        2000,
        1,
        1,
        true,
        false
    );
    await gamePoolWeek.configure(
        gamePoolDay.address,
        gameToken.address,
        gamePoolMonth.address,
        2000,
        2,
        2,
        false,
        false
    );
    await gamePoolMonth.configure(
        gamePoolWeek.address,
        gameToken.address,
        ethers.constants.AddressZero,
        0,
        3,
        3,
        false,
        false
    );
    await gameTicket.setRewardPool(gamePoolDay.address);

    return { buyToken, gameTicket, gameConfig, gameToken, gamePoolDay, gamePoolWeek, gamePoolMonth };
}

interface GameAirdropFixture {
    gameToken: GameToken
    gameAirdrop: GameAirdrop
}

export const gameAirdropFixture: Fixture<GameAirdropFixture> = async function (): Promise<GameAirdropFixture> {
    let gameTokenFactory = await ethers.getContractFactory('GameToken');
    let gameToken = (await gameTokenFactory.deploy()) as GameToken;
    await gameToken.initialize();


    let airdropFactory = await ethers.getContractFactory('GameAirdrop');
    let gameAirdrop = (await airdropFactory.deploy()) as GameAirdrop;


    await gameAirdrop.initialize(
        gameToken.address,
        bigNumber18.mul(100),
        BigNumber.from(dateNow),
        BigNumber.from(dateNow).add(259200) // 3 days
    )

    await gameToken.increaseFund(gameAirdrop.address, bigNumber18.mul(1000));

    return { gameToken, gameAirdrop }
}

interface GamePoolsFixture {
    buyToken: TestToken
    gameToken: GameToken
    gameTicket: GameTicket
    gameTicket2: GameTicket2
    gamePool: GamePool
    gamePoolActivity: GamePoolActivity
    gamePoolCS: GamePoolCS
}

export const gamePoolsFixture: Fixture<GamePoolsFixture> = async function ([wallet, other]: Wallet[]): Promise<GamePoolsFixture> {
    const gameTicketFactory = await ethers.getContractFactory('GameTicket');
    const gameTicket2Factory = await ethers.getContractFactory('GameTicket2');
    const gamePoolFactory = await ethers.getContractFactory('GamePool');
    const gamePoolActivityFactory = await ethers.getContractFactory('GamePoolActivity');
    const gamePoolCSFactory = await ethers.getContractFactory('GamePoolCS');
    const gameTokenFactory = await ethers.getContractFactory('GameToken');
    const testTokenFactory = await ethers.getContractFactory('TestToken')
    const gameConfigFactory = await ethers.getContractFactory('GameConfig');

    const gameConfig = (await gameConfigFactory.deploy()) as GameConfig;
    await gameConfig.initialize();

    let buyToken = (await testTokenFactory.deploy()) as TestToken
    await buyToken.initialize();

    let gameToken = (await gameTokenFactory.deploy()) as GameToken;
    await gameToken.initialize();
    await gameToken.increaseFund(wallet.address, ethers.constants.MaxUint256);

    let gameTicket = (await gameTicketFactory.deploy()) as GameTicket;
    await gameTicket.initialize(buyToken.address, bigNumber18);
    await gameTicket.setupConfig(gameConfig.address);

    let gameTicket2 = (await gameTicket2Factory.deploy()) as GameTicket2;
    await gameTicket2.initialize(buyToken.address, gameToken.address, bigNumber18, bigNumber18.mul(10), bigNumber18.mul(100));
    await gameTicket2.setupConfig(gameConfig.address);


    let gamePool = (await gamePoolFactory.deploy()) as GamePool;
    await gamePool.initialize();
    await gamePool.setupConfig(gameConfig.address);
    let gamePoolActivity = (await gamePoolActivityFactory.deploy()) as GamePoolActivity;
    await gamePoolActivity.initialize();
    await gamePoolActivity.setupConfig(gameConfig.address);
    let gamePoolCS = (await gamePoolCSFactory.deploy()) as GamePoolCS;
    await gamePoolCS.initialize();
    await gamePoolCS.setupConfig(gameConfig.address);

    await gamePool.configure(
        gameTicket.address,
        gameToken.address,
        gamePoolCS.address,
        2000,
        1,
        1,
        true,
        false
    );

    await gamePoolActivity.configure(
        gameTicket2.address,
        gameToken.address,
        gamePoolCS.address,
        1,
        0,
        true,
        false
    );

    await gamePoolCS.configure(
        buyToken.address,
        gameToken.address,
        1,
        0,
        false
    );

    await gameTicket.setRewardPool(gamePool.address);
    await gameTicket2.setRewardPool(gamePoolActivity.address);

    return { buyToken, gameToken, gameTicket, gameTicket2, gamePool, gamePoolActivity, gamePoolCS }
}

interface GameTimeLockFixture {
    lockToken: TestToken
    gameTimeLock: GameTimeLock
}

export const gameTimeLockFixture: Fixture<GameTimeLockFixture> = async function ([wallet]: Wallet[]): Promise<GameTimeLockFixture> {
    let testTokenFactory = await ethers.getContractFactory('TestToken')
    let lockToken = (await testTokenFactory.deploy()) as TestToken
    await lockToken.initialize();

    let gameTimeLockFactory = await ethers.getContractFactory('GameTimeLock')
    let gameTimeLock = (await gameTimeLockFactory.deploy()) as GameTimeLock
    await gameTimeLock.initialize(lockToken.address, BigNumber.from(5))

    await lockToken.mint(wallet.address, bigNumber18.mul(10000));
    return { lockToken, gameTimeLock }
}

interface GameSchedualPoolFixture {
    depositToken: TestToken
    rewardToken: GameToken
    gameTimeLock: MockContract
    pool: GameSchedualPool
}

export const gameSchedualPoolFixture: Fixture<GameSchedualPoolFixture> = async function ([wallet, other]: Wallet[]): Promise<GameSchedualPoolFixture> {
    let testTokenFactory = await ethers.getContractFactory('TestToken')
    let depositToken = (await testTokenFactory.deploy()) as TestToken
    await depositToken.initialize();
    await depositToken.mint(wallet.address, bigNumber18.mul(10000));

    let rewardTokenFactory = await ethers.getContractFactory('GameToken');
    let rewardToken = (await rewardTokenFactory.deploy()) as GameToken;
    await rewardToken.initialize();

    let gameTimeLock = await deployMockContract(wallet, TimeLockABI)
    await gameTimeLock.mock.lock.returns()

    let poolFactory = await ethers.getContractFactory('GameSchedualPool');
    let pool = (await poolFactory.deploy()) as GameSchedualPool
    await pool.initialize(
        depositToken.address,
        rewardToken.address,
        BigNumber.from('1640966400'),
        bigNumber18.mul(10),
        BigNumber.from(0),
        BigNumber.from(0),
        gameTimeLock.address
    );
    await rewardToken.increaseFund(pool.address, ethers.constants.MaxUint256);

    return { depositToken, rewardToken, gameTimeLock, pool };
}

interface GameFarmFixture {
    depositToken1: TestToken
    depositToken2: TestToken
    rewardToken: GameToken
    gameTimeLock: MockContract
    farm: GameFarm
}

export const gameFarmFixture: Fixture<GameFarmFixture> = async function ([wallet, other]: Wallet[]): Promise<GameFarmFixture> {
    let testTokenFactory = await ethers.getContractFactory('TestToken')
    let depositToken1 = (await testTokenFactory.deploy()) as TestToken
    await depositToken1.initialize();
    await depositToken1.mint(wallet.address, bigNumber18.mul(10000));

    let depositToken2 = (await testTokenFactory.deploy()) as TestToken
    await depositToken2.initialize();
    await depositToken2.mint(wallet.address, bigNumber18.mul(10000));

    let rewardTokenFactory = await ethers.getContractFactory('GameToken');
    let rewardToken = (await rewardTokenFactory.deploy()) as GameToken;
    await rewardToken.initialize();

    let gameTimeLock = await deployMockContract(wallet, TimeLockABI)
    await gameTimeLock.mock.lock.returns()

    let farmFactory = await ethers.getContractFactory('GameFarm');
    let farm = (await farmFactory.deploy()) as GameFarm
    await farm.initialize(
        rewardToken.address,
        bigNumber18.mul(10),
        BigNumber.from(0),
        BigNumber.from(0),
        gameTimeLock.address
    );
    await rewardToken.increaseFund(farm.address, ethers.constants.MaxUint256);

    await depositToken1.approve(farm.address, ethers.constants.MaxUint256)
    await depositToken1.transfer(other.address, bigNumber18.mul(100))
    await depositToken1.connect(other).approve(farm.address, ethers.constants.MaxUint256)

    await depositToken2.approve(farm.address, ethers.constants.MaxUint256)
    await depositToken2.transfer(other.address, bigNumber18.mul(100))
    await depositToken2.connect(other).approve(farm.address, ethers.constants.MaxUint256)

    return { depositToken1, depositToken2, rewardToken, gameTimeLock, farm };
}

interface GameSinglePoolFixture {
    depositToken: TestToken
    rewardToken: GameToken
    pool: GameSinglePool
}

export const gameSinglePoolFixture: Fixture<GameSinglePoolFixture> = async function ([wallet, other]: Wallet[]): Promise<GameSinglePoolFixture> {
    let testTokenFactory = await ethers.getContractFactory('TestToken')
    let depositToken = (await testTokenFactory.deploy()) as TestToken
    await depositToken.initialize();
    await depositToken.mint(wallet.address, bigNumber18.mul(10000));

    let rewardTokenFactory = await ethers.getContractFactory('GameToken');
    let rewardToken = (await rewardTokenFactory.deploy()) as GameToken;
    await rewardToken.initialize();
    await rewardToken.increaseFund(wallet.address, bigNumber18.mul(10000))
    await rewardToken.mint(wallet.address, bigNumber18.mul(1000));

    let poolFactory = await ethers.getContractFactory('GameSinglePool');
    let pool = (await poolFactory.deploy()) as GameSinglePool
    await pool.initialize(
        wallet.address,
        depositToken.address,
        rewardToken.address,
        BigNumber.from(0),
        bigNumber18.mul(10),
        BigNumber.from(1)
    );

    await depositToken.approve(pool.address, ethers.constants.MaxUint256)
    await rewardToken.approve(pool.address, ethers.constants.MaxUint256)
    await depositToken.transfer(other.address, bigNumber18.mul(100))
    await depositToken.connect(other).approve(pool.address, ethers.constants.MaxUint256)

    return { depositToken, rewardToken, pool };
}

interface GameTicketExchangeFixture {
    usdt: TestToken
    busd: TestToken
    sqt: GameToken
    weth: WETH9
    gameLevel1Ticket: GameTicket
    gameLevel2Ticket: MockGameTicket
    factory: PancakeFactory
    pancakeRouter: PancakeRouter
    gameTicketExchange: GameTicketExchange
}

export const gameTicketExchangeFixture: Fixture<GameTicketExchangeFixture> = async function ([wallet, other]: Wallet[]): Promise<GameTicketExchangeFixture> {
    // deploy usdt
    let testTokenFactory = await ethers.getContractFactory('TestToken')
    let usdt = (await testTokenFactory.deploy()) as TestToken
    await usdt.initialize();
    await usdt.mint(wallet.address, bigNumber18.mul(100000000));

    // deploy busd
    let busd = (await testTokenFactory.deploy()) as TestToken
    await busd.initialize();
    await busd.mint(wallet.address, bigNumber18.mul(100000000));

    // deploy sqt
    let gameTokenFactory = await ethers.getContractFactory('GameToken');
    let sqt = (await gameTokenFactory.deploy()) as GameToken;
    await sqt.initialize();
    await sqt.increaseFund(wallet.address, bigNumber18.mul(100000000))
    await sqt.mint(wallet.address, bigNumber18.mul(100000000));

    // deploy weth
    let wethFactory = await ethers.getContractFactory('WETH9')
    let weth = (await wethFactory.deploy()) as WETH9

    // deploy game config
    const gameConfigFactory = await ethers.getContractFactory('GameConfig');
    const gameConfig = (await gameConfigFactory.deploy()) as GameConfig;
    await gameConfig.initialize();

    // deploy game ticket
    const gameTicket1Factory = await ethers.getContractFactory('GameTicket');
    const gameLevel1Ticket = (await gameTicket1Factory.deploy()) as GameTicket;
    await gameLevel1Ticket.initialize(usdt.address, bigNumber18);
    await gameLevel1Ticket.setupConfig(gameConfig.address);

    // deploy game ticket2
    const gameTicket2Factory = await ethers.getContractFactory('MockGameTicket');
    const gameLevel2Ticket = (await gameTicket2Factory.deploy()) as MockGameTicket;
    await gameLevel2Ticket.initialize(usdt.address, sqt.address, bigNumber18, bigNumber18, bigNumber18);
    await gameLevel2Ticket.setupConfig(gameConfig.address);

    // deploy pancake factory
    const panacakeFactory = await ethers.getContractFactory('PancakeFactory')
    const factory = (await panacakeFactory.deploy(wallet.address)) as PancakeFactory

    // deploy pancake router
    const pancakeRouterFactory = await ethers.getContractFactory('PancakeRouter')
    const pancakeRouter = (await pancakeRouterFactory.deploy(factory.address, weth.address)) as PancakeRouter

    // usdt approve to pancake router
    await usdt.approve(pancakeRouter.address, ethers.constants.MaxUint256)

    // busd approve to pancake router
    await busd.approve(pancakeRouter.address, ethers.constants.MaxUint256)

    // sqt approve to pancake router
    await sqt.approve(pancakeRouter.address, ethers.constants.MaxUint256)

    // add liquidity busd-usdt 1:1
    await pancakeRouter.addLiquidity(
        busd.address,
        usdt.address,
        bigNumber18.mul(10000),
        bigNumber18.mul(10000),
        BigNumber.from(0),
        BigNumber.from(0),
        wallet.address,
        deadline
    )

    // add liquidity weth-usdt 1:100
    await pancakeRouter.addLiquidityETH(
        usdt.address,
        bigNumber18.mul(5000),
        BigNumber.from(0),
        BigNumber.from(0),
        wallet.address,
        deadline,
        { value: bigNumber18.mul(50) }
    )

    // add liquidity sqt-usdt 10:1
    await pancakeRouter.addLiquidity(
        sqt.address,
        usdt.address,
        bigNumber18.mul(100000),
        bigNumber18.mul(10000),
        BigNumber.from(0),
        BigNumber.from(0),
        wallet.address,
        deadline
    )


    // deploy game ticket exchange
    const gameTicketExchangeFactory = await ethers.getContractFactory('GameTicketExchange');
    const gameTicketExchange = (await gameTicketExchangeFactory.deploy()) as GameTicketExchange;
    await gameTicketExchange.initialize(weth.address, pancakeRouter.address)

    // add level ticket
    await gameTicketExchange.batchSetLevelTicket(
        [BigNumber.from(1), BigNumber.from(2)],
        [gameLevel1Ticket.address, gameLevel2Ticket.address]
    )

    // add payment token whiteList
    await gameTicketExchange.batchSetPTW(
        [busd.address, usdt.address, sqt.address, ethers.constants.AddressZero],
        [true, true, true, true]
    )

    return { usdt, busd, sqt, weth, gameLevel1Ticket, gameLevel2Ticket, pancakeRouter, factory, gameTicketExchange }
}

interface GamePredictionFixture {
    sqt: GameToken
    gamePrediction: GamePrediction
}

export const gamePredictionFixture: Fixture<GamePredictionFixture> = async function ([wallet]: Wallet[]): Promise<GamePredictionFixture> {
    // deploy sqt
    let gameTokenFactory = await ethers.getContractFactory('GameToken');
    let sqt = (await gameTokenFactory.deploy()) as GameToken;
    await sqt.initialize();
    await sqt.increaseFund(wallet.address, bigNumber18.mul(100000000))
    await sqt.mint(wallet.address, bigNumber18.mul(100000000));

    // deploy game prediction
    let gamePredictionFactory = await ethers.getContractFactory('GamePrediction')
    let gamePrediction = (await gamePredictionFactory.deploy()) as GamePrediction;
    await gamePrediction.initialize(bigNumber17, wallet.address)

    // add round 1
    await gamePrediction.addRound(
        BigNumber.from(5),
        BigNumber.from((Date.now() / 1000).toFixed(0)),
        BigNumber.from((Date.now() / 1000 + 2999).toFixed(0)),
        sqt.address
    )

    // add round 2
    await gamePrediction.addRound(
        BigNumber.from(5),
        BigNumber.from((Date.now() / 1000).toFixed(0)),
        BigNumber.from((Date.now() / 1000 + 3000).toFixed(0)),
        ethers.constants.AddressZero
    )

    return { sqt, gamePrediction }
}

interface GameNFTMarketFixture {
    sqt: GameToken
    competitorTicket: GameCompetitorTicket
    betTicket: GameBetTicket
    hat: GameNFT
    market: GameNFTMarket
}

export const gameNFTMarketFixture: Fixture<GameNFTMarketFixture> = async function ([wallet]: Wallet[]): Promise<GameNFTMarketFixture> {
    // deploy sqt
    let gameTokenFactory = await ethers.getContractFactory('GameToken');
    let sqt = (await gameTokenFactory.deploy()) as GameToken;
    await sqt.initialize();
    await sqt.increaseFund(wallet.address, bigNumber18.mul(100000000))
    await sqt.mint(wallet.address, bigNumber18.mul(100000000));

    // deploy competitor ticket
    let competitorTicketFactory = await ethers.getContractFactory('GameCompetitorTicket')
    let competitorTicket = (await competitorTicketFactory.deploy(
        "456",
        "257",
        "25183704",
        "https://squidgame.live/cometitorTicket/",
        ".jpeg",
        "Squidgame Competitor Ticket NFT",
        "SCTNFT"
    )) as GameCompetitorTicket
    
    // deploy bet ticket
    let betTicketFactory = await ethers.getContractFactory('GameBetTicket')
    let betTicket = (await betTicketFactory.deploy(
        "Avator",
        "SQTA",
        "1",
        "10",
        "https://squidgame.live/avatornft/",
        ".svg"
    )) as GameBetTicket
    
    // deploy hat
    let hatFactory = await ethers.getContractFactory('GameNFT')
    let hat = (await hatFactory.deploy(
        "Hat",
        "SQTH",
        "5",
        "https://squidgame.live/hatnft/",
        ".png"
    )) as GameNFT
    
    // deploy market
    let marketFactory = await ethers.getContractFactory('GameNFTMarket')
    let market = (await marketFactory.deploy()) as GameNFTMarket
    await market.initialize(wallet.address, wallet.address, BigNumber.from(9999))

    // set whiteList to wallet and market
    await competitorTicket.setWhiteLists([wallet.address, market.address], [true, true])
    await betTicket.setWhiteLists([wallet.address, market.address], [true, true])
    await hat.setWhiteLists([wallet.address, market.address], [true, true])
    // batch add sell nft conf
    await market.batchSetConf([
        {
            nft: competitorTicket.address,
            paymentToken: sqt.address,
            price: bigNumber18,
            startTime: (Date.now()/1000 - 86400).toFixed(0),
            endTime: (Date.now()/1000 + 86400).toFixed(0),
            total: BigNumber.from(1000),
            minId: BigNumber.from(1),
            maxId: BigNumber.from(200),
            isRand: false,
            isLottery: true
        },
        {
            nft: betTicket.address,
            paymentToken: ethers.constants.AddressZero,
            price: bigNumber18,
            startTime: (Date.now()/1000 - 86400).toFixed(0),
            endTime: (Date.now()/1000 + 86400).toFixed(0),
            total: BigNumber.from(10),
            minId: BigNumber.from(1),
            maxId: BigNumber.from(10),
            isRand: true,
            isLottery: false
        },
        {
            nft: hat.address,
            paymentToken: ethers.constants.AddressZero,
            price: bigNumber18,
            startTime: (Date.now()/1000 - 86400).toFixed(0),
            endTime: (Date.now()/1000 + 86400).toFixed(0),
            total: BigNumber.from(5),
            minId: BigNumber.from(0),
            maxId: BigNumber.from(0),
            isRand: false,
            isLottery: false
        }
    ])
    return {sqt, competitorTicket, betTicket, hat, market}
}

async function signRandom(wallet: Wallet, seeds: Array<string>, addr: string): Promise<string> {
    let message = ethers.utils.solidityKeccak256(['uint256[]', 'address'], [seeds, addr])
    let s = await network.provider.send('eth_sign', [wallet.address, message])
    return s;
}

export { signRandom }