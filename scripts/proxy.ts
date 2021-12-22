const { ethers, upgrades, network } = require("hardhat");
import {sleep} from "sleep-ts";
import fs from "fs";
import path from "path";
let filePath = path.join(__dirname, `.data.json`);
let data: any = {
};

async function loadConfig() {
  let _filePath = path.join(__dirname, `.data.json`);
  if (fs.existsSync(_filePath)) {
    filePath = _filePath;
  }
  console.log('filePath:', filePath);
}


function updateConstructorArgs(contractName: string, address: string) {
  for (let k in data) {
    for (let i in data[k].constructorArgs) {
      let v = "${" + contractName + ".address}";
      if (data[k].constructorArgs[i] == v) {
        data[k].constructorArgs[i] = address;
      }
    }
  }
}

function updateUpgradeArgsArgs(name: string, address: string) {
  for (let k in data) {
    for (let i in data[k].upgradeArgs) {
      let v = "${" + name + ".address}";
      if (data[k].upgradeArgs[i] == v) {
        data[k].upgradeArgs[i] = address;
      }
    }
  }
}

async function before() {
  await loadConfig();
  if (fs.existsSync(filePath)) {
    let rawdata = fs.readFileSync(filePath);
    data = JSON.parse(rawdata.toString());
    for (let k in data) {
      if (data[k].address != "") {
        updateUpgradeArgsArgs(k, data[k].address);
      }
    }
  }
}

async function after() {
  let content = JSON.stringify(data, null, 2);
  fs.writeFileSync(filePath, content);
}


async function deployContract(name: string, value: any) {
  if (data[name].deployed) {
    console.log(`Deploy contract ${name} exits: "${data[name].address}",`)
    return;
  }
  let contractName = name;
  if(data[name].hasOwnProperty('contractName')) {
    contractName = data[name].contractName;
  }
  // console.log('Deploy contract...', contractName, value)
  const Factory = await ethers.getContractFactory(contractName);
  let ins = await Factory.deploy(...value.constructorArgs);
  await ins.deployed();
  data[name].address = ins.address;
  data[name].deployed = true;
  data[name].upgraded = true;
  data[name].verified = false;
  console.log(`Deploy contract ${name} new: "${ins.address}",`)
  updateConstructorArgs(name, ins.address);
}

async function deployProxyContract(name: string, value: any) {
  // Deploying
  if (data[name].deployed) {
    console.log(`Deploy contract ${name} exits: "${data[name].address}",`)
    return;
  }
  // console.log('deploy...')
  await sleep(100);
  let contractName = name;
  if(data[name].hasOwnProperty('contractName')) {
    contractName = data[name].contractName;
  }
  const Factory = await ethers.getContractFactory(contractName);
  const ins = await upgrades.deployProxy(Factory, data[name].upgradeArgs);
  await ins.deployed();
  data[name].address = ins.address;
  data[name].deployed = true;
  data[name].upgraded = true;
  data[name].verified = false;
  console.log(`Deploy contract ${name} new: "${ins.address}",`)
  updateUpgradeArgsArgs(name, ins.address);
}

async function upgradeContract(name: string, value: any) {
  // Upgrading
  if(!data[name].deployed || !data[name].address || data[name].upgraded) {
    return
  }
  // console.log('upgrade...', data[name].address)
  let contractName = name;
  if(data[name].hasOwnProperty('contractName')) {
    contractName = data[name].contractName;
  }
  const Factory = await ethers.getContractFactory(contractName);
  const ins = await upgrades.upgradeProxy(data[name].address, Factory);
  data[name].address = ins.address;
  data[name].deployed = true;
  data[name].upgraded = true;
  data[name].verified = false;
  console.log(`Upgrade contract ${name} : "${ins.address}",`)
}

async function deploy() {
  console.log("============Start to deploy project's contracts.============");
  for (let k in data) {
    try {
      if(data[k].hasOwnProperty('onlyDeploy') && data[k].onlyDeploy) {
        await deployContract(k, data[k])
      } else {
        await deployProxyContract(k, data[k])
      }
    } catch(e) {
      console.error('deployContract except', k, e)
    }
  }
  console.log("======================Deploy Done!.=====================");
}


async function upgrade() {
  console.log("============Start to upgrade project's contracts.============");
  for (let k in data) {
    try {
      await upgradeContract(k, data[k])
    } catch(e) {
      console.error('upgradeContract except', k, e)
    }
  }
  console.log("======================Upgrade Done!.=====================");
}



async function main() {
  await before();
  await deploy();
  await upgrade();
  await after();
}

main();
