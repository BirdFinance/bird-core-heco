// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/Math.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './LPTokenWrapper.sol';

contract InvitationDualPool is LPTokenWrapper, Ownable
{
    IERC20 public token1;
    IERC20 public token2;

    uint256 constant public OneDay = 1 days;
    uint256 constant public Percent = 100;

    uint256 public starttime;
    uint256 public periodFinish = 0;
    //note that, you should combine the bonus rate to get the final production rate
    uint256 public reward1Rate = 0;
    uint256 public reward2Rate = 0;

    //for inviter to get invitation bonus in target token
    uint256 public bonusRatio = 0;
    //for tax if you getReward, pay the ratio in source token
    uint256 public taxRatio = 0;

    uint256 public lastUpdateTime;


    uint256 public rewardPerTokenStored1;
    uint256 public rewardPerTokenStored2;


    mapping(address => uint256) public userRewardPerTokenPaid1;
    mapping(address => uint256) public userRewardPerTokenPaid2;

    mapping(address => uint256) public rewards1;
    mapping(address => uint256) public rewards2;


    mapping(address => uint256) public accumulatedRewards1;
    mapping(address => uint256) public accumulatedRewards2;


    mapping(address => address) public inviter;
    mapping(address => address[]) public invitees;


    mapping(address => uint256) public bonus1;
    mapping(address => uint256) public bonus2;


    mapping(address => uint256) public accumulatedBonus1;
    mapping(address => uint256) public accumulatedBonus2;

    address public minerOwner1;
    address public minerOwner2;

    address public defaultInviter;
    address taxCollector;
    IERC20 public checkToken;

    address public feeManager;

    uint256 public fee = 0.02 ether;
    bool internal feeCharged = false;
    bool internal cooldownMarked = false;

    uint256 public withdrawCoolDown;
    //address => stake timestamp
    mapping(address => uint256) public withdrawCoolDownMap;

    event RewardAdded1(uint256 reward);
    event RewardAdded2(uint256 reward);

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    event RewardPaid1(address indexed user, uint256 reward);
    event RewardPaid2(address indexed user, uint256 reward);

    event BonusPaid1(address indexed user, uint256 reward);
    event BonusPaid2(address indexed user, uint256 reward);

    event TransferBack(address token, address to, uint256 amount);

    constructor(
        address _token1, //target
        address _token2, //target

        address _lptoken, //source
        uint256 _starttime,
        address _minerOwner1,
        address _minerOwner2,

        address _defaultInviter,
        address _taxCollector,
        IERC20 _checkToken,
        address _feeManager,
        uint256 _withdrawCoolDown
    ) public {
        require(_token1 != address(0), "_token1 is zero address");
        require(_token2 != address(0), "_token2 is zero address");

        require(_lptoken != address(0), "_lptoken is zero address");

        require(_minerOwner1 != address(0), "_minerOwner1 is zero address");
        require(_minerOwner2 != address(0), "_minerOwner2 is zero address");

        token1 = IERC20(_token1);
        token2 = IERC20(_token2);

        lpt = IERC20(_lptoken);
        starttime = _starttime;
        minerOwner1 = _minerOwner1;
        minerOwner2 = _minerOwner2;

        defaultInviter = _defaultInviter;
        taxCollector = _taxCollector;
        checkToken = _checkToken;
        feeManager = _feeManager;
        withdrawCoolDown = _withdrawCoolDown;
    }


    modifier checkStart() {
        require(block.timestamp >= starttime, 'Pool: not start');
        _;
    }

    modifier checkCoolDown(bool onlyRefresh){
        bool lock = false;
        if (!cooldownMarked) {
            cooldownMarked = true;
            lock = true;

            //!!!!!!!!!!!!only stake will set this and stake is the first and last chained action
            if (!onlyRefresh) {
                require(withdrawCoolDownMap[msg.sender].add(withdrawCoolDown) <= block.timestamp, "Cooling Down");
            }
        }
        _;
        if (lock) {
            cooldownMarked = false;
            withdrawCoolDownMap[msg.sender] = block.timestamp;
        }
    }

    modifier updateInviter(address _inviter){
        address userInviter = inviter[msg.sender];
        if (userInviter == address(0)) {
            if (_inviter == address(0)) {
                inviter[msg.sender] = defaultInviter;
                //invitees[defaultInviter].push(msg.sender);
            } else {
                if (_inviter == msg.sender) {
                    _inviter = defaultInviter;
                }

                if (address(checkToken) != address(0)) {
                    if (balanceOf(_inviter) == 0 && checkToken.balanceOf(_inviter) == 0) {
                        _inviter = defaultInviter;
                    }
                }

                inviter[msg.sender] = _inviter;
                invitees[_inviter].push(msg.sender);
            }
        } else {
            if (_inviter != address(0)) {
                require(userInviter == _inviter, "you can't change your inviter");
            }
        }
        _;
    }

    modifier chargeFee(){
        bool lock = false;
        if (!feeCharged) {
            require(msg.value >= fee, "msg.value >= minimumFee");
            payable(feeManager).transfer(msg.value);
            feeCharged = true;
            lock = true;
        }
        _;
        if (lock) {
            feeCharged = false;
        }
    }


    //有人stake或者withdraw,totalSupply变了
    modifier updateReward(address account) {

        rewardPerTokenStored1 = rewardPerToken1();
        rewardPerTokenStored2 = rewardPerToken2();

        //全局变量
        lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {//initSet或者updateReward之外的

            rewards1[account] = earned1(account);
            //balance变了,导致balance*rewardPerToken的公式失效
            userRewardPerTokenPaid1[account] = rewardPerTokenStored1;
            //从现在开始 之前的记为debt

            rewards2[account] = earned2(account);
            userRewardPerTokenPaid2[account] = rewardPerTokenStored2;

        }
        _;
    }

    //累计计算RewardPerToken,用到了最新时间lastTimeRewardApplicable()
    //在updateReward的时候被调用,说明rate或者totalSupply变了
    function rewardPerToken1() public view returns (uint256) {
        if (totalSupply() == 0) {
            //保持不变
            return rewardPerTokenStored1;
        }
        return
        rewardPerTokenStored1.add(
            lastTimeRewardApplicable()//根据最后更新的时间戳 计算差值
            .sub(lastUpdateTime)
            .mul(reward1Rate)
            .mul(1e18)
            .div(totalSupply())
        );
    }

    function rewardPerToken2() public view returns (uint256) {
        if (totalSupply() == 0) {
            //保持不变
            return rewardPerTokenStored2;
        }
        return
        rewardPerTokenStored2.add(
            lastTimeRewardApplicable()//根据最后更新的时间戳 计算差值
            .sub(lastUpdateTime)
            .mul(reward2Rate)
            .mul(1e18)
            .div(totalSupply())
        );
    }

    //008cc262
    //earned需要读取最新的rewardPerToken
    function earned1(address account) public view returns (uint256) {
        return
        balanceOf(account)
        .mul(rewardPerToken1().sub(userRewardPerTokenPaid1[account]))//要减去debt
        .div(1e18)
        .add(rewards1[account]);
        //每次更新debt的时候,也会更行rewards(因为balance变了,balance*rewardPerToken的计算会失效),所以要加回来
    }

    function earned2(address account) public view returns (uint256) {
        return
        balanceOf(account)
        .mul(rewardPerToken2().sub(userRewardPerTokenPaid2[account]))//要减去debt
        .div(1e18)
        .add(rewards2[account]);
        //每次更新debt的时候,也会更行rewards(因为balance变了,balance*rewardPerToken的计算会失效),所以要加回来
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    //7acb7757
    function stake(uint256 amount, address _inviter)
    public
    payable
    updateReward(msg.sender)
    checkStart
    updateInviter(_inviter)
    //chargeFee
    checkCoolDown(true)
    {
        require(amount > 0, 'Pool: Cannot stake 0');
        super.lpStake(amount);
        emit Staked(msg.sender, amount);
    }

    //2e1a7d4d1
    function withdraw(uint256 amount)
    public
    payable
    updateReward(msg.sender)
    checkStart
    chargeFee
    checkCoolDown(false)
    {
        require(amount > 0, 'Pool: Cannot withdraw 0');
        super.lpWithdraw(amount);

        if (isTaxOn()) {
            clearReward();
        }

        emit Withdrawn(msg.sender, amount);
    }

    //e9fad8ee
    function exit() external payable chargeFee checkCoolDown(false) {
        getReward();
        getBonus();
        withdraw(balanceOf(msg.sender));
    }

    //3d18b912
    //hook the bonus when user getReward
    function getReward() public payable updateReward(msg.sender) checkStart chargeFee checkCoolDown(false) {
        uint256 reward1 = earned1(msg.sender);
        if (reward1 > 0) {
            rewards1[msg.sender] = 0;
            token1.safeTransferFrom(minerOwner1, msg.sender, reward1);
            emit RewardPaid1(msg.sender, reward1);
            accumulatedRewards1[msg.sender] = accumulatedRewards1[msg.sender].add(reward1);

            address userInviter = inviter[msg.sender];
            uint256 userBonus1 = reward1.mul(bonusRatio).div(Percent);
            bonus1[userInviter] = bonus1[userInviter].add(userBonus1);

            if (isTaxOn()) {
                uint256 amount = balanceOf(msg.sender).mul(taxRatio).div(Percent);
                lpPayTax(amount, taxCollector);
            }
        }

        uint256 reward2 = earned2(msg.sender);
        if (reward2 > 0) {
            rewards2[msg.sender] = 0;
            token2.safeTransferFrom(minerOwner2, msg.sender, reward2);
            emit RewardPaid2(msg.sender, reward2);
            accumulatedRewards2[msg.sender] = accumulatedRewards2[msg.sender].add(reward2);

            address userInviter = inviter[msg.sender];
            uint256 userBonus2 = reward2.mul(bonusRatio).div(Percent);
            bonus2[userInviter] = bonus2[userInviter].add(userBonus2);
        }

        if (reward1 > 0 || reward2 > 0) {
            if (isTaxOn()) {
                uint256 amount = balanceOf(msg.sender).mul(taxRatio).div(Percent);
                lpPayTax(amount, taxCollector);
            }
        }
    }

    function clearReward() internal updateReward(msg.sender) checkStart {
        uint256 reward1 = earned1(msg.sender);
        if (reward1 > 0) {
            rewards1[msg.sender] = 0;
        }

        uint256 reward2 = earned2(msg.sender);
        if (reward2 > 0) {
            rewards2[msg.sender] = 0;
        }
    }

    //8bdff161
    function getBonus() public payable checkStart chargeFee checkCoolDown(false) {
        uint256 userBonus1 = bonus1[msg.sender];
        if (userBonus1 > 0) {
            bonus1[msg.sender] = 0;
            token1.safeTransferFrom(minerOwner1, msg.sender, userBonus1);
            emit BonusPaid1(msg.sender, userBonus1);
            accumulatedBonus1[msg.sender] = accumulatedBonus1[msg.sender].add(userBonus1);
        }

        uint256 userBonus2 = bonus2[msg.sender];
        if (userBonus2 > 0) {
            bonus2[msg.sender] = 0;
            token2.safeTransferFrom(minerOwner2, msg.sender, userBonus2);
            emit BonusPaid2(msg.sender, userBonus2);
            accumulatedBonus2[msg.sender] = accumulatedBonus2[msg.sender].add(userBonus2);
        }
    }

    //0eb88e5
    function getRewardAndBonus() external payable chargeFee checkCoolDown(false) {
        getReward();
        getBonus();
    }

    function transferBack(IERC20 erc20Token, address to, uint256 amount) external onlyOwner {
        require(erc20Token != lpt, "For LPT, transferBack is not allowed, if you transfer LPT by mistake, sorry");

        if (address(erc20Token) == address(0)) {
            payable(to).transfer(amount);
        } else {
            erc20Token.safeTransfer(to, amount);
        }
        emit TransferBack(address(erc20Token), to, amount);
    }

    function isTaxOn() internal view returns (bool){
        return taxRatio != 0;
    }

    //you can call this function many time as long as block.number does not reach starttime and _starttime
    function initSet(uint256 _starttime, uint256 reward1PerDay, uint256 reward2PerDay, uint256 _bonusRatio, uint256 _taxRatio, uint256 _periodFinish)
    external
    onlyOwner
    updateReward(address(0))
    {

        require(block.timestamp < starttime, "block.timestamp < starttime");

        require(block.timestamp < _starttime, "block.timestamp < _starttime");
        require(_starttime < _periodFinish, "_starttime < _periodFinish");

        starttime = _starttime;
        reward1Rate = reward1PerDay.div(OneDay);
        reward2Rate = reward2PerDay.div(OneDay);
        bonusRatio = _bonusRatio;
        taxRatio = _taxRatio;
        periodFinish = _periodFinish;
        lastUpdateTime = starttime;
    }

    function updateRewardRate(uint256 reward1PerDay, uint256 reward2PerDay, uint256 _bonusRatio, uint256 _taxRatio, uint256 _periodFinish)
    external
    onlyOwner
    updateReward(address(0))
    {
        if (_periodFinish == 0) {
            _periodFinish = block.timestamp;
        }

        require(starttime < block.timestamp, "starttime < block.timestamp");
        require(block.timestamp <= _periodFinish, "block.timestamp <= _periodFinish");

        reward1Rate = reward1PerDay.div(OneDay);
        reward2Rate = reward2PerDay.div(OneDay);

        bonusRatio = _bonusRatio;
        taxRatio = _taxRatio;
        periodFinish = _periodFinish;
        lastUpdateTime = block.timestamp;
    }

    function changeDefaultInviter(address _defaultInviter) external onlyOwner {
        defaultInviter = _defaultInviter;
    }

    function changeBonusRatio(uint256 _bonusRatio) external onlyOwner {
        bonusRatio = _bonusRatio;
    }

    function changeMinerOwner(address _minerOwner1, address _minerOwner2) external onlyOwner {
        minerOwner1 = _minerOwner1;
        minerOwner2 = _minerOwner2;

    }

    function changeTaxCollector(address _taxCollector) external onlyOwner {
        taxCollector = _taxCollector;
    }

    function changeFee(
        uint256 _fee,
        address _feeManager
    ) external onlyOwner {
        fee = _fee;
        feeManager = _feeManager;
    }

    function changeWithdrawCoolDown(uint256 _withdrawCoolDown) external onlyOwner {
        withdrawCoolDown = _withdrawCoolDown;
    }

    function changeCheckToken(IERC20 _checkToken) external onlyOwner {
        checkToken = _checkToken;
    }
}
