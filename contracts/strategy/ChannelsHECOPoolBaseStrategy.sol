// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import "../controller/IController.sol";
import "../strategy/IStrategy.sol";
import "../mdex/IMdexRouter.sol";
import "../mdex/IMdexPair.sol";
import "./BaseStrategy.sol";
import "../mdex/ISwapMining.sol";
import "../rewardPool/IChannelsPool.sol";

abstract contract ChannelsHECOPoolBaseStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IChannelsPool public pool;
    ISwapMining public swapMining;
    IMdexPair internal canUsdtPair;
    address usdtForDex;

    constructor(
        IVault _vault,
        IController _controller,
        IERC20 _capital, //Can-HUSD_lp Can_HT_lp
        address _swapRouter,
        IERC20 _rewardToken,
        IChannelsPool _pool,
        ISwapMining _swapMining,
        uint256 _profitFee,
        IMdexPair _canUsdtPair,
        address _usdtForDex
    )BaseStrategy(_vault, _controller, _capital, _swapRouter, _rewardToken, _profitFee) public {
        pool = _pool;

        swapMining = _swapMining;
        canUsdtPair = _canUsdtPair;
        usdtForDex = _usdtForDex;
    }

    //mostly called from vault and public
    //deposit all capital into pool
    function invest() public permitted override {
        uint256 balance = balanceOfStrategy();
        if (balance > 0) {
            capital_.safeApprove(address(pool), 0);
            capital_.safeApprove(address(pool), balance);
            pool.stake(balance);
        }
    }

    function emergencyWithdraw(uint256 _amount) public onlyOwner {
        if (_amount != 0) {
            revert("stake-mining-pool not supported");
        }
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    // amount maybe not enough
    function withdrawToVault(uint256 amount) restricted external override {
        uint256 balance = balanceOfStrategy();
        //not enough
        if (balance < amount) {
            withdraw(amount.sub(balance));
        }
        balance = balanceOfStrategy();
        capital_.safeTransfer(address(vault_), balance);
    }


    function withdrawAllToVault() restricted external override {
        //if there are capital left in heco pool, get all back
        uint256 balance = balanceOfPool();
        if (balance != 0) {
            pool.withdraw(balance);
        }

        //withdraw will also returns reward, so must do a compound exchange reward -> capital
        compound();
        //nothing should left in heco pool
        balance = balanceOfStrategy();
        capital_.safeTransfer(address(vault_), balance);
    }

    // deposit 0 can claim all pending amount
    function getPoolReward() internal {
        pool.getReward();
    }

    function withdraw(uint256 _amount) internal {
        pool.withdraw(_amount);
    }

    function balanceOfStrategy() public view returns (uint256) {
        return capital_.balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256 ret) {
        ret = pool.balanceOf(address(this));
        return ret;
    }

    function capitalBalance() public override view returns (uint) {
        return balanceOfStrategy()
        .add(balanceOfPool());
    }

    function withdrawSwapMining() onlyOwner external {
        uint256 balanceBefore = rewardToken.balanceOf(address(this));
        swapMining.takerWithdraw();
        uint256 balanceAfter = rewardToken.balanceOf(address(this));
        rewardToken.safeTransfer(controller.feeManager(), balanceAfter.sub(balanceBefore));
    }

    function setSwapMining(ISwapMining _swapMining) onlyOwner external {
        swapMining = _swapMining;
    }

    function getPoolRewardApy() override external view returns (uint256 apy100){
        //apy = totalProduction in usdt over one year / total stake in usdt
        uint256 canPerSecond = pool.rewardRate();

        uint256 totalAmount = pool.totalSupply();
        //rewardToken is can
        uint256 totalProductionPerYear = canPerSecond.mul(365 * 86400);

        //price = usdt / can
        (uint256 usdt,uint256 can,) = IMdexPair(canUsdtPair).getReserves();
        if (IMdexPair(canUsdtPair).token1() == usdtForDex) {
            uint256 temp = usdt;
            usdt = can;
            can = temp;
        }
        /*
                totalProductionPerYear * usdt / can
        apy =  -----------------------------------------------
                 totalAmount * capitalPrice / 10**18
        */
        apy100 = totalProductionPerYear.mul(baseCent).mul(usdt).mul(baseDecimal).div(can).div(totalAmount).div(this.getCapitalPrice());
    }
}
