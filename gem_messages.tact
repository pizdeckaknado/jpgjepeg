const ONE_TON: Int = ton("1");  
const MIN_INVEST: Int = ton("0.1");  
const MIN_DEPOSIT: Int = ton("0.1");  
const MIN_ACTION_INTERVAL: Int = 0; 
const INIT_MARKET_EGGS: Int = 108_000_000_000;  
const LEVEL1_PERCENT: Int = 75;        
const LEVEL2_PERCENT: Int = 20;        
const LEVEL3_PERCENT: Int = 5;         
const REFERRAL_PERCENT: Int = 15;      
const HIRE_REFERRAL_PERCENT: Int = 5;  
const EGGS_TO_HATCH_1MINERS: Int = 1080000;  
const FEE_PERCENT: Int = 8;
const WITHDRAWAL_THRESHOLD: Int = 300;    
fun getPlayerAddress(ownerAddress: Address, registryAddress: Address, registryOwner: Address): Address {
    let init = initOf GemPlayer(ownerAddress, registryAddress, registryOwner);
    return contractAddress(init);
}
fun calculateTrade(rt: Int, rs: Int, bs: Int): Int {
    require(rt > 0 && rs > 0, "Invalid trade parameters");
    return (bs * rt) / (rt + rs);
}
struct DepositInfo {
    amount: Int;       
    miners: Int;       
    withdrawn: Int;    
    health: Int;       
}
struct UpdatePlayer {
    lastHatch: Int;
    upgradeCount: Int;
    referrer: Address?;
    referralRewards: Int;
    totalDeposit: Int;
    totalMiners: Int;     
    totalWithdrawn: Int;
    registrationTime: Int;  
    depositCounter: Int;
}
message(0x7361d09c) BuyMiners {
    referrer: Address;  
    investAmount: Int;
}
struct RegistryInfo {
    marketEggs: Int;
    balance: Int;        
    devFeeBalance: Int;  
    referralBalance: Int; 
    eggsBuyPrice: Int;
    owner: Address;
}
message(0x7361d09d) BuyMinersFor {
    targetAddress: Address;    
    referrer: Address;         
    investAmount: Int;
}
message(0x7362d09c) SellGems {
}
message(0x7363d09c) ClaimRewards {
}
message(0x7364d09c) CollectDevFee {
}
message(0x7365d09c) HireMiners {
}
message(0x7366d09c) WithdrawReferralRewards {
    amount: Int;  
    to: Address;  
    ownerAddress: Address;  
}
message EggBuyResult {
    amount: Int;       
    eggs: Int;         
    referrer: Address; 
}
message UpdateReferralReward {
    amount: Int;      
    senderAddress: Address;  
}
message ProcessNextLevelReward {
    amount: Int;      
    senderAddress: Address;  
}
message ProcessLastLevelReward {
    amount: Int;
    senderAddress: Address;
}
message UpdateMarketEggs {
    eggAmount: Int;
    ownerAddress: Address;  
    referrer: Address?; 
}
message SellEggsAndWithdraw {
    eggs: Int;              
    ownerAddress: Address;  
    playerOwner: Address;   
}
message SellEggsComplete {
    amount: Int;            
    equivalentEggs: Int;    
}
