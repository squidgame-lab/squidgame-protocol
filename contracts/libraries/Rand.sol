// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

library Rand {
    // return result>=0, result< _max
    function randIndex(uint _seed, uint _max) internal view returns (uint result){
        require(_seed > 0, 'RAND: ZERO');
        uint lastBlockNumber = block.number - 1;
        uint hashVal = uint(blockhash(lastBlockNumber));
        return uint((uint(hashVal) / _seed)) % _max;
    }

    // return result>0, result<= _max
    function randNumber(uint _seed, uint _max) internal view returns (uint result){
        result = randIndex(_seed, _max);
        if(result == 0) result = _max;
        return result;
    }
}