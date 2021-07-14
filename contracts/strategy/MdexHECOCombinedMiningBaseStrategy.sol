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
import "../rewardPool/IHecoMdexCombinedMining.sol";

abstract contract MdexHECOCombinedMiningBaseStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IHecoMdexCombinedMining public pool;
    uint256 public poolID;
    ISwapMining public swapMining;
    IMdexPair internal coinUsdtPair;
    address usdtForDex;

    constructor(
        IVault _vault,
        IController _controller,
        IERC20 _capital,
        address _swapRouter,
        IERC20 _rewardToken,
        IHecoMdexCombinedMining _pool,
        uint256 _poolID,
        ISwapMining _swapMining,
        uint256 _profitFee,
        IMdexPair _coindUsdtPair,
        address _usdtForDex
    )BaseStrategy(_vault, _controller, _capital, _swapRouter, _rewardToken, _profitFee) public {
        pool = _pool;
        poolID = _poolID;

        address _lpt;
        (_lpt,,,,) = pool.poolInfo(poolID);
        require(_lpt == address(capital_), "Pool Info does not match capital");
        swapMining = _swapMining;
        coinUsdtPair = _coindUsdtPair;
        usdtForDex = _usdtForDex;
    }

    //mostly called from vault and public
    //deposit all capital into pool
    function invest() public permitted override {
        uint256 balance = balanceOfStrategy();
        if (balance > 0) {
            capital_.safeApprove(address(pool), 0);
            capital_.safeApprove(address(pool), balance);
            pool.deposit(poolID, balance);
        }
    }

    function emergencyWithdraw(uint256 _amount) public onlyOwner {
        if (_amount != 0) {
            pool.emergencyWithdraw(_amount);
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
            pool.withdraw(poolID, balance);
        }

        //withdraw will also returns reward, so must do a compound exchange reward -> capital
        compound();
        //nothing should left in heco pool
        balance = balanceOfStrategy();
        capital_.safeTransfer(address(vault_), balance);
    }

    // deposit 0 can claim all pending amount
    function getPoolReward() internal {
        pool.deposit(poolID, 0);
    }

    function withdraw(uint256 _amount) internal {
        pool.withdraw(poolID, _amount);
    }

    function balanceOfStrategy() public view returns (uint256) {
        return capital_.balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256 ret) {
        (ret,) = pool.userInfo(poolID, address(this));
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
        (,uint256 allocPoint,,,uint256 coinAmount) = pool.poolInfo(poolID);
        uint256 coinPerBlock = pool.coinPerBlock();
        uint256 totalAllocPoint = pool.totalAllocPoint();
        //underlying block time is 3 seconds
        //rewardToken is mdx
        uint256 totalProductionPerYear = coinPerBlock.mul(10512000).mul(allocPoint).div(totalAllocPoint);

        //price = usdt / coin
        (uint256 usdt,uint256 coin,) = IMdexPair(coinUsdtPair).getReserves();
        if (IMdexPair(coinUsdtPair).token1() == usdtForDex) {
            uint256 temp = usdt;
            usdt = coin;
            coin = temp;
        }

        /*
                totalProductionPerYear * usdt / coin
        apy =  -----------------------------------------------
                 totalAmount * capitalPrice / 10**18
        */
        apy100 = totalProductionPerYear.mul(baseCent).mul(usdt).mul(baseDecimal).div(coin).div(coinAmount).div(this.getCapitalPrice());
    }
}
