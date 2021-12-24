// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

library Rand {
    // return result>=0, result< _max
    function randIndex(uint _blockNumber, uint _seed, uint _max) internal view returns (uint){
        require(_seed > 0, 'RAND: SEED_ZERO');
        require(_blockNumber < block.number, 'RAND: OVER_BLOCK');
        uint seed = computerSeed(_blockNumber, _seed);
        return seed % _max;
    }

    // return result>=0, result< _max
    function randIndex(uint _seed, uint _max) internal view returns (uint){
        return randIndex(block.number - 1, _seed, _max);
    }

    // return result>0, result<= _max
    function randNumber(uint _blockNumber, uint _seed, uint _max) internal view returns (uint){
        uint result = randIndex(_blockNumber, _seed, _max);
        if(result == 0) result = _max;
        return result;
    }
    
    function randNumber(uint _seed, uint _max) internal view returns (uint){
        return randNumber(block.number - 1, _seed, _max);
    }

    function randNumberBetween(uint256 _min, uint256 _max) internal view returns (uint){
        return randNumberBetween(block.number - 1, block.number, _min, _max);
    }

    function randNumberBetween(uint _seed, uint256 _min, uint256 _max) internal view returns (uint){
        return randNumberBetween(block.number - 1, _seed, _min, _max);
    }

    function randNumberBetween(uint _blockNumber, uint _seed, uint256 _min, uint256 _max) internal view returns (uint){
        require(_min < _max, "Invalid range");
        uint seed = computerSeed(_blockNumber, _seed);
        return (seed % (_max - _min + 1)) + _min;
    }

    function computerSeed(uint _blockNumber, uint _seed) internal view returns (uint256) {
        require(_seed > 0, 'RAND: SEED_ZERO');
        require(_blockNumber < block.number, 'RAND: OVER_BLOCK');
        uint hashVal = uint(blockhash(_blockNumber));
        hashVal -= block.timestamp;
        return (hashVal / _seed);
    }
}