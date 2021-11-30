// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

interface IGamePool {
        
    struct RoundData {
        uint128 ticketTotal;
        uint128 winTotal;
        uint128 rewardTotal;
        uint128 scoreTotal;
        uint128 topScoreTotal;
        uint128 topStrategySn;
        uint128 shareParticipationAmount;
        uint128 shareTopAmount;
        uint64 startTime;
        uint64 releaseBlockStart;
        uint64 releaseBlockEnd;
    }

    function shareToken() external view returns (address);
    function shareParticipationAmount() external view returns (uint128);
    function shareTopAmount() external view returns (uint128);
    function historys(uint) external view returns (RoundData memory);
    function totalRound() external view returns (uint64);
}
