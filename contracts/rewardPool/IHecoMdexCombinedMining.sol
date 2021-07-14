// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0 <0.8.0;

//mdx/??lp -> ??coin
interface IHecoMdexCombinedMining {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function pending(uint256 _pid, address _user) external view returns (uint256);

    //we don't care multLpRewardDebt
    function userInfo(uint256 _pid, address _user) external view returns (uint256 amount, uint256 rewardDebt);

    /*
    uint256 lpSupply;
    if (address(pool.lpToken) == coin) {
        lpSupply = pool.coinAmount;
    } else {
        lpSupply = pool.lpToken.balanceOf(address(this));
    }
    if (lpSupply == 0) {
        pool.lastRewardBlock = number;
        return;
    }
    */
    function poolInfo(uint256 _pid) external view returns (address lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accCoinPerShare, uint256 coinAmount);

    function emergencyWithdraw(uint256 pid) external;

    function poolLength() external view returns (uint256);

    function coinPerBlock() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);
}
