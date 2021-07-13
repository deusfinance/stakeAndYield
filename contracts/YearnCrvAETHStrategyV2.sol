pragma solidity 0.6.12;

// SPDX-License-Identifier: MIT

import "./SafeMath.sol";
import "./Ownable.sol";

interface StandardToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStakeAndYield {
    function getRewardToken() external view returns(address);
    function totalSupply(uint256 stakeType) external view returns(uint256);
    function totalYieldWithdrawed() external view returns(uint256);
    function notifyRewardAmount(uint256 reward, uint256 stakeType) external;
}

interface IController {
    function withdrawETH(uint256 amount) external;

    function depositTokenForStrategy(
        uint256 amount, 
        address yearnVault
    ) external;

    function buyForStrategy(
        uint256 amount,
        address rewardToken,
        address recipient
    ) external;

    function withdrawForStrategy(
        uint256 sharesToWithdraw, 
        address yearnVault
        ) external;

    function strategyBalance(address stra) external view returns(uint256);
}

interface IYearnVault{
    function balanceOf(address account) external view returns (uint256);
    function withdraw(uint256 amount) external;
    function getPricePerFullShare() external view returns(uint256);
    function deposit(uint256 _amount) external returns(uint256);
}


contract YearnCrvAETHStrategyV2 is Ownable {
    using SafeMath for uint256;

    uint256 public PERIOD = 7 days;

    //TODO: get from old contract and update it
    uint256 public START_PERIOD = 1622027294;

    uint256 public lastEpochTime;
    uint256 public lastBalance;

     uint256 public ethPushedToYearn;

     IStakeAndYield public vault;

    IController public controller;
    
    //crvAETH 
    address yearnDepositableToken = 0xaA17A236F2bAdc98DDc0Cf999AbB47D47Fc0A6Cf;

    IYearnVault public yearnVault = IYearnVault(0x132d8D2C76Db3812403431fAcB00F3453Fc42125);
    

    address public operator = msg.sender;


    uint256 public minRewards = 0.01 ether;
    uint256 public minDepositable = 0.05 ether;

    modifier onlyOwnerOrOperator(){
        require(
            msg.sender == owner() || msg.sender == operator,
            "!owner"
        );
        _;
    }

    constructor(
        address _vault,
        address _controller
    ) public{
        vault = IStakeAndYield(_vault);
        controller = IController(_controller);
    }

    function epoch(
        uint256 _rewards,
        uint256 _withdrawAmountETH,
        uint256 _withdrawShares,
        uint256 _depositAmountETH,
        uint256 _depositAmountAETH
    ) public onlyOwnerOrOperator{
        lastBalance = vault.totalSupply(2);
        if(_rewards > minRewards){
            // get DEA and send to Vault
            controller.buyForStrategy(
                _rewards,
                vault.getRewardToken(),
                address(vault)
            );
        }
        ethPushedToYearn = ethPushedToYearn.sub(
            _withdrawAmountETH
        ).add(_depositAmountETH);

        if(_withdrawShares > 0){
            withdrawFromYearn(_withdrawShares);
        }

        if(_depositAmountAETH >= minDepositable){
            //deposit to yearn
            controller.depositTokenForStrategy(
                _depositAmountAETH,
                address(yearnVault));
        }

        lastEpochTime = block.timestamp;
    }

    function withdrawFromYearn(uint256 sharesToWithdraw) private returns(uint256){
        uint256 yShares = controller.strategyBalance(address(this));
        require(yShares >= sharesToWithdraw, "Not enough shares");

        controller.withdrawForStrategy(
            sharesToWithdraw, 
           address(yearnVault)
        );
    }

    
    function pendingBalance() public view returns(uint256){
        uint256 vaultBalance = vault.totalSupply(2);
        if(vaultBalance < lastBalance){
            return 0;
        }
        return vaultBalance.sub(lastBalance);
    }

    function getLastEpochTime() public view returns(uint256){
        return lastEpochTime;
    }

    function getNextEpochTime() public view returns(uint256){
        uint256 periods = (now - START_PERIOD)/PERIOD;
        return START_PERIOD + (periods+1)*PERIOD;
    }

    function setOperator(address _addr) public onlyOwner{
        operator = _addr;
    }

    function setMinRewards(uint256 _val) public onlyOwner{
        minRewards = _val;
    }

    function setMinDepositable(uint256 _val) public onlyOwner{
        minDepositable = _val;
    }

    function setController(address _controller, address _vault) public onlyOwner{
        if(_controller != address(0)){
            controller = IController(_controller);
        }
        if(_vault != address(0)){
            vault = IStakeAndYield(_vault);
        }
    }

    function setPeriods(uint256 period, uint256 startPeriod) public onlyOwner{
        PERIOD = period;
        START_PERIOD = startPeriod;
    }

    function setEthPushedToYearn(uint256 _val) public onlyOwner{
        ethPushedToYearn = _val;
    }

    function setYearnDepositableToken(address token) public onlyOwner{
        yearnDepositableToken = token;
    }

    function setYearnVault(address addr) public onlyOwner{
        yearnVault = IYearnVault(addr);
    }

    function emergencyWithdrawETH(uint256 amount, address addr) public onlyOwner{
        require(addr != address(0));
        payable(addr).transfer(amount);
    }

    function emergencyWithdrawERC20Tokens(address _tokenAddr, address _to, uint _amount) public onlyOwner {
        StandardToken(_tokenAddr).transfer(_to, _amount);
    }
}
