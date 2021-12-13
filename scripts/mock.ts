import { BigNumber } from "@ethersproject/bignumber";
import { ethers } from "hardhat";
import { sleep } from "sleep-ts";

// tokens
const weth = '0x7FcCaDD3e6A3F80e194CaDf13FeDF36B9BBbe98F'
const usdt = '0x337610d27c682E347C9cD60BD4b3b107C9d34dDd'
const busd = '0xCC36337919dCE00519eb7a7013C97e79cC33D14f' // mock busd
const sqt = '0x9505D2C9a5CF3977a33babC55E3582607E877D15'

// dexs
let uniswapV2Dexs = [
  {
    name: "burgerswapFactory",
    factory: '0xd7C239C284b6509bc1AcA6169A319A30eBC96C96',
    router: '0x5B47446A34e7a6cfd7a3D8ffED62Fb2baC3cDd03',
    sqt2wethPair: '0xF30635215D8fa82821c0C13715965f0C921Af757',
    sqt2usdtPair: '0x90216EDc722d14482954Fdcf240f8fB4D54E7a0E'
  },
  {
    name: "pancakeFactory",
    factory: '0x962E0fCc3f7E1b7e900dE12EDD67758ffE183aaB',
    router: '0x8EFfCF3a721FF6169be25b225d06728B7Fe3411A',
    sqt2wethPair: '',
    sqt2usdtPair: ''
  }
]

// constants
const bigNumber18 = BigNumber.from('1000000000000000000');
const bigNumber17 = BigNumber.from('100000000000000000');
const deadLine = BigNumber.from('1640966400');

async function waitForMint(tx: any) {
  let result = null
  do {
    result = await ethers.provider.getTransactionReceipt(tx)
    await sleep(500)
  } while (result === null)
  await sleep(500)
}

async function deployDexBurgerSwapV2(name: string) {
  console.log(`============start to deploy ${name} dex============`);
  let signer = ethers.provider.getSigner();
  let wallet = await signer.getAddress();

  // deploy factory
  let factoryFactory = await ethers.getContractFactory('BurgerSwapV2Factory')
  let factoryIns = await factoryFactory.deploy();
  await factoryIns.deployed();
  console.log('deploy factory success: ', factoryIns.address);

  // deploy router
  let routerFactory = await ethers.getContractFactory('BurgerSwapV2Router')
  let routerIns = await routerFactory.deploy(factoryIns.address, weth);
  await routerIns.deployed();
  console.log('deploy router success: ', routerIns.address);

  // usdt approve to router
  let usdtIns = await ethers.getContractAt('ERC20Token', usdt);
  let tx = await usdtIns.approve(routerIns.address, bigNumber18.mul('10000000000'));
  await waitForMint(tx.hash);
  console.log('usdt approve success: ', tx.hash);

  // sqt approve to router
  let sqtIns = await ethers.getContractAt('ERC20Token', sqt);
  tx = await sqtIns.approve(routerIns.address, bigNumber18.mul('10000000000'));
  await waitForMint(tx.hash);
  console.log('sqt approve success: ', tx.hash);

  // add liquidity sqt-usdt 100:10
  tx = await routerIns.addLiquidity(
    sqt,
    usdt,
    bigNumber18.mul(100),
    bigNumber18.mul(10),
    0,
    0,
    wallet,
    deadLine
  )
  await waitForMint(tx.hash);
  console.log('add liquidity sqt-usdt success: ', tx.hash);

  // add liquidity sqt-weth 100:0.5
  tx = await routerIns.addLiquidityETH(
    sqt,
    bigNumber18.mul(100),
    0,
    0,
    wallet,
    deadLine,
    { value: bigNumber17.mul(5) }
  )
  await waitForMint(tx.hash);
  console.log('add liquidity sqt-weth success: ', tx.hash);

  console.log(`============end to deploy ${name} dex============\n\n`);
}

async function deployDexPancake(name: string) {
  console.log(`============start to deploy ${name} dex============`);
  let signer = ethers.provider.getSigner();
  let wallet = await signer.getAddress();

  // deploy factory
  let factoryFactory = await ethers.getContractFactory('PancakeFactory')
  let factoryIns = await factoryFactory.deploy(wallet);
  await factoryIns.deployed();
  console.log('deploy factory success: ', factoryIns.address);

  // deploy router
  let routerFactory = await ethers.getContractFactory('PancakeRouter')
  let routerIns = await routerFactory.deploy(factoryIns.address, weth);
  await routerIns.deployed();
  console.log('deploy router success: ', routerIns.address);

  // usdt approve to router
  let usdtIns = await ethers.getContractAt('ERC20Token', usdt);
  let tx = await usdtIns.approve(routerIns.address, bigNumber18.mul('10000000000'));
  await waitForMint(tx.hash);
  console.log('usdt approve success: ', tx.hash);

  // sqt approve to router
  let sqtIns = await ethers.getContractAt('ERC20Token', sqt);
  tx = await sqtIns.approve(routerIns.address, bigNumber18.mul('10000000000'));
  await waitForMint(tx.hash);
  console.log('sqt approve success: ', tx.hash);

  // busd approve to router
  let busdIns = await ethers.getContractAt('ERC20Token', busd);
  tx = await busdIns.approve(routerIns.address, bigNumber18.mul('10000000000'));
  await waitForMint(tx.hash);
  console.log('busd approve success: ', tx.hash);

  // let routerIns = await ethers.getContractAt('PancakeRouter', "0x8EFfCF3a721FF6169be25b225d06728B7Fe3411A");
  // add liquidity usdt-sqt 20:200
  tx = await routerIns.addLiquidity(
    sqt,
    usdt,
    bigNumber18.mul(200),
    bigNumber18.mul(20),
    0,
    0,
    wallet,
    deadLine
  )
  await waitForMint(tx.hash);
  console.log('add liquidity usdt-sqt success: ', tx.hash);

  // add liquidity usdt-busd 30:30
  tx = await routerIns.addLiquidity(
    busd,
    usdt,
    bigNumber18.mul(30),
    bigNumber18.mul(30),
    0,
    0,
    wallet,
    deadLine,
    {gasPrice: 6}
  )
  await waitForMint(tx.hash);
  console.log('add liquidity usdt-busd success: ', tx.hash);

  // add liquidity usdt-weth 30:0.3
  tx = await routerIns.addLiquidityETH(
    usdt,
    bigNumber18.mul(30),
    0,
    0,
    wallet,
    deadLine,
    { value: bigNumber17.mul(3) }
  )
  await waitForMint(tx.hash);
  console.log('add liquidity usdt-weth success: ', tx.hash);

  console.log(`============end to deploy ${name} dex============\n\n`);
}

async function main() {
  // await deployDexBurgerSwapV2(uniswapV2Dexs[0].name);
  await deployDexPancake(uniswapV2Dexs[1].name);
}


main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });