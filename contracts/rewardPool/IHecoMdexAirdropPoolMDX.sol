// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0 <0.8.0;

//mdx/??lp -> mdex
interface IHecoMdexAirdropPoolMDX {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function pending(uint256 _pid, address _user) external view returns (uint256);

    //we don't care multLpRewardDebt
    function userInfo(uint256 _pid, address _user) external view returns (uint256 amount, uint256 rewardDebt);

    /*
    this is weired to keep mdx separately, no way to open 2 same mdx->mdx pools
    uint256 lpSupply;
    if (address(pool.lpToken) == mdx) {
        lpSupply = pool.mdxAmount;
    } else {
        lpSupply = pool.lpToken.balanceOf(address(this));
    }
    */
    function poolInfo(uint256 _pid) external view returns (address lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accMdxPerShare, uint256 mdxAmount);

    function emergencyWithdraw(uint256 pid) external;

    function poolLength() external view returns (uint256);

    function mdxPerBlock() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);
}
