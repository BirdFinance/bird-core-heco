// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0 <0.8.0;

interface IChannelsPool {
    function stake(uint256 amount) external; //质押

    function withdraw(uint256 amount) external; //提现

    function getReward() external; //领取奖励

    function exit() external; // 提现并领取奖励

    function earned(address account) external view returns (uint256); //查询奖励

    function rewardRate() external view returns (uint); //查询总奖励速率，每秒奖励的can数量

    //质押的lp
    function totalSupply() external view returns (uint256);//盲猜的

    function balanceOf(address) external view returns (uint256);//盲猜的

    function rewardPerTokenStored() external view returns (uint256);//盲猜的
}
