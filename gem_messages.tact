const ONE_TON: Int = 1000000000;  
const MIN_INVEST: Int = 100000000;
const MIN_DEPOSIT: Int = 100000000;  
const MIN_ACTION_INTERVAL: Int = 0; 
const INIT_MARKET_EGGS: Int = 108000000000;
const MIN_GAS: Int = ton("0.033");  
const MINIMUM_GAS: Int = ton("0.02");  
const STD_GAS: Int = ton("0.1");  
const DEPLOY_GAS: Int = ton("0.1");  
const MODE_REGULAR: Int = 0;        
const MODE_CARRY_ALL: Int = 1;      
const MODE_IGNORE_ERRORS: Int = 2;  
const MODE_BOUNCE: Int = 34;        
const MODE_RETURN_GAS: Int = 64;    
const LEVEL1_PERCENT: Int = 75;        
const LEVEL2_PERCENT: Int = 20;        
const LEVEL3_PERCENT: Int = 5;         
const REFERRAL_PERCENT: Int = 15;      
const HIRE_REFERRAL_PERCENT: Int = 5;  
const MAX_DEPTH: Int = 3;  
const PSN: Int = 10000;
const PSNH: Int = 5000;
const EGGS_TO_HATCH_1MINERS: Int = 1080000;  
const FEE_PERCENT: Int = 8;
const WITHDRAWAL_THRESHOLD: Int = 300;    
struct MaybeAddress {
    isSet: Bool;
    value: Address;
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
    referrer: MaybeAddress;
    referralRewards: Int;
    totalDeposit: Int;
    totalMiners: Int;     
    totalWithdrawn: Int;
    registrationTime: Int;  
    depositCounter: Int;
}
message(0x7361d09c) BuyMiners {
    referrer: Address;  
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
    depth: Int;       
    senderAddress: Address;  
}
message ProcessNextLevelReward {
    amount: Int;      
    depth: Int;       
    senderAddress: Address;  
}
message UpdateMarketEggs {
    eggAmount: Int;
    ownerAddress: Address;  
    referrer: MaybeAddress; 
}
message(0xd3b92c11) CalculateEggBuyAndUpdate {
    amount: Int;
    ownerAddress: Address;  
}
message SellEggsAndWithdraw {
    eggs: Int;              
    ownerAddress: Address;  
    playerOwner: Address;   
}
message SellEggsComplete {
    amount: Int;            
    marketEggs: Int;        
    registryBalance: Int;   
}
