import { ethers, network } from "hardhat";
import fs from "fs";
import path from "path";
import {sleep} from "sleep-ts";
let chainId = 0;
let dataPath = path.join(__dirname, `.data.json`);
let setupPath = path.join(__dirname, `.setup.json`);
let data: any = [
]


async function loadConfig() {
  chainId = await network.provider.send("eth_chainId");
  chainId = Number(chainId);
  let _dataPath = path.join(__dirname, `.data.json`);
  if (fs.existsSync(_dataPath)) {
    dataPath = _dataPath;
  }
  let _setupPath = path.join(__dirname, `.setup.json`);
  if (fs.existsSync(_setupPath)) {
    setupPath = _setupPath;
  }
  console.log('dataPath:', dataPath);
  console.log('setupPath:', setupPath);
}

async function waitForMint(tx:any) {
  let result = null
  do {
    result = await ethers.provider.getTransactionReceipt(tx)
    await sleep(1000)
  } while (result === null)
  await sleep(1000)
}

function replaceData(search:any, src:any, target:any) {
  if(Array.isArray(src)) {
    for(let i in src) {
      if ((src[i]+'').indexOf(search) != -1) {
        src[i] = src[i].replace(src[i], target);
      }
    }
  } else if ((src+'').indexOf(search) != -1) {
    src = src.replace(src, target);
  }
  return src;
}


function updateCallData(name: string, address: string) {
  for (let k in data) {
    if (data[k].name == name && data[k].contractAddr == "") {
      data[k].contractAddr = address;
    }
    for (let i in data[k].args) {
      let v = "${" + name + ".address}";
      data[k].args[i] = replaceData(v, data[k].args[i], address);
    }
  }
}

async function updateArgsFromData() {
  if (fs.existsSync(dataPath)) {
    let rawdata = fs.readFileSync(dataPath);
    let _data = JSON.parse(rawdata.toString());
    for (let k in _data) {
      if (_data[k].address != "") {
        updateCallData(k, _data[k].address);
      }
    }
  }
}

async function call() {
  for (let k in data) {
    if (data[k].call && data[k].contractAddr != "" && data[k].name != "") {
      console.log(` =============== Call ${data[k].name}.${data[k].functionName} ...`)
      await sleep(100)
      let contractName = data[k].name;
      if(data[k].hasOwnProperty('contractName')) {
        contractName = data[k].contractName;
      }
      let ins = await ethers.getContractAt(contractName, data[k].contractAddr)
      let tx = await ins[data[k].functionName](...data[k].args)
      await waitForMint(tx.hash)
      console.log(` =============== Call ${data[k].name}.${data[k].functionName} txhash: `, tx.hash)
    }
  }
}

async function before() {
  await loadConfig();
  if (fs.existsSync(setupPath)) {
    let rawData = fs.readFileSync(setupPath)
    data = JSON.parse(rawData.toString())
    await updateArgsFromData()
  }
}

async function main() {
  await before();
  await call();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
  