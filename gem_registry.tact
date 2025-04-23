import "@stdlib/deploy";
import "@stdlib/ownable";
import "./messages"; 
import "./player"; 
contract GemRegistry with OwnableTransferable, Deployable {
    owner: Address;
    marketEggs: Int;
    devFeeBalance: Int;  
    referralBalance: Int;  
    init() {
        self.owner = sender();
        self.marketEggs = INIT_MARKET_EGGS;
        self.devFeeBalance = 0;
        self.referralBalance = 0;
    }
    fun calculatePlayerAddress(ownerAddress: Address): Address {
        let init = initOf GemPlayer(ownerAddress, myAddress(), self.owner);
        return contractAddress(init);
    }
    fun isPlayerContract(addr: Address, ownerAddress: Address): Bool {
        if (addr == newAddress(0, 0)) {
            return false;
        }
        let calculatedAddress = self.calculatePlayerAddress(ownerAddress);
        return calculatedAddress == addr;
    }
    fun calculateMinersForAmount(amount: Int): Int {
        let buyableEggs = self.calculateEggBuy(amount);
        return buyableEggs / EGGS_TO_HATCH_1MINERS;
    }
    fun calculateTrade(rt: Int, rs: Int, bs: Int): Int {
        require(rt > 0 && rs > 0, "Invalid trade parameters");
        let numerator = PSN * bs * rt;
        let denominator = PSNH * rt + PSN * rs + PSNH * rt;
        return numerator / denominator;
    }
    fun availableBalance(): Int {
        return max(myBalance() - self.devFeeBalance - self.referralBalance, 0);
    }
    fun max(a: Int, b: Int): Int {
        if (a > b) {
            return a;
        }
        return b;
    }
    fun calculateEggBuy(eth: Int): Int {
        let availableBal = self.availableBalance();
        let adjustedBalance = availableBal - eth;
        if (adjustedBalance <= 0) {
            adjustedBalance = 1; 
        }
        return self.calculateTrade(eth, adjustedBalance, self.marketEggs);
    }
    fun calculateEggSell(eggs: Int): Int {
        return self.calculateTrade(eggs, self.marketEggs, self.availableBalance());
    }
    receive(msg: UpdateMarketEggs) {
        let senderAddr = sender();
        require(self.isPlayerContract(senderAddr, msg.ownerAddress), "Only player contract can call this");
        self.marketEggs = self.marketEggs + msg.eggAmount;
        let totalEggsSpent = msg.eggAmount * 5;
        let referralEggs = (totalEggsSpent * HIRE_REFERRAL_PERCENT) / 100;
        let referralTonValue = self.calculateEggSell(referralEggs);
        let MIN_REFERRAL_TON: Int = ton("0.15");
        if (referralTonValue >= MIN_REFERRAL_TON) {
            let gasValue = STD_GAS;
            let rewardAmount = referralTonValue - gasValue;
            self.referralBalance = self.referralBalance + rewardAmount;
            let referrerContractAddr = msg.referrer.value;
            send(SendParameters{
                to: referrerContractAddr,
                value: gasValue,
                mode: MODE_REGULAR,
                body: UpdateReferralReward{
                    amount: rewardAmount,
                    depth: 0
                }.toCell()
            });
        }
    }
    receive(msg: SellEggsAndWithdraw) {
        let senderAddr = sender();
        require(self.isPlayerContract(senderAddr, msg.playerOwner), "Only player contract can call this");
        let eggValue = self.calculateEggSell(msg.eggs);
        require(eggValue > 0, "No value for eggs");
        let fee = (eggValue * FEE_PERCENT) / 100;
        let withdrawAmount = eggValue - fee;
        let availableBal = self.availableBalance();
        require(availableBal >= withdrawAmount, "Insufficient balance for withdrawal");
        self.devFeeBalance = self.devFeeBalance + fee;
        self.marketEggs = self.marketEggs + msg.eggs;
        send(SendParameters{
            to: msg.ownerAddress,
            value: withdrawAmount,
            mode: MODE_REGULAR,
            body: "TON.AG".asComment()
        });
        send(SendParameters{
            to: senderAddr,
            value: ton("0.2"), 
            mode: MODE_RETURN_GAS, 
            body: SellEggsComplete{
                amount: withdrawAmount,
                marketEggs: self.marketEggs,
                registryBalance: self.availableBalance()
            }.toCell()
        });
    }
    receive(msg: CalculateEggBuyAndUpdate) {
        let senderAddr = sender();
        require(self.isPlayerContract(senderAddr, msg.ownerAddress), "Only player contract can call this");
        let eggAmount = self.calculateEggBuy(msg.amount);
        send(SendParameters{
            to: senderAddr,
            value: STD_GAS,
            mode: MODE_RETURN_GAS, 
            body: EggBuyResult{
                amount: msg.amount,
                eggs: eggAmount,
                referrer: newAddress(0, 0) 
            }.toCell()
        });
    }
    fun deployPlayerContract(owner: Address): Address {
        let playerAddress = self.calculatePlayerAddress(owner);
        let init = initOf GemPlayer(owner, myAddress(), self.owner);
        send(SendParameters{
            to: playerAddress,
            value: DEPLOY_GAS, 
            mode: MODE_REGULAR, 
            body: null,
            code: init.code,
            data: init.data
        });
        return playerAddress;
    }
    receive(msg: BuyMiners) {
        let sender = context().sender;
        let value = context().value;
        require(value >= MIN_INVEST, "Minimum investment not met");
        let devFee = (value * FEE_PERCENT) / 100;
        let gasForResponse = STD_GAS+STD_GAS;
        let refReward = (value * REFERRAL_PERCENT) / 100;
        let investValue = value - devFee - gasForResponse - refReward;
        require(investValue > 0, "Investment too small after fees");
        self.devFeeBalance = self.devFeeBalance + devFee;
        self.referralBalance = self.referralBalance + refReward;
        let playerAddress = self.calculatePlayerAddress(sender);
        let init = initOf GemPlayer(sender, myAddress(), self.owner);
        let eggs = self.calculateEggBuy(investValue);
        let referrerAddress = msg.referrer;
        if (referrerAddress == sender) {
            referrerAddress = newAddress(0, 0); 
        }
        send(SendParameters{
            to: playerAddress,
            value: gasForResponse,
            mode: MODE_REGULAR,
            body: EggBuyResult{
                amount: investValue,
                eggs: eggs,
                referrer: referrerAddress 
            }.toCell(),
            code: init.code,
            data: init.data
        });
    }
    receive(msg: BuyMinersFor) {
        let sender = context().sender;
        let value = context().value;
        require(value >= MIN_INVEST, "Minimum investment not met");
        let devFee = (value * FEE_PERCENT) / 100;
        let gasForResponse = MIN_GAS;
        let refReward = (value * REFERRAL_PERCENT) / 100;
        let investValue = value - devFee - gasForResponse - refReward;
        require(investValue > 0, "Investment too small after fees");
        self.devFeeBalance = self.devFeeBalance + devFee;
        self.referralBalance = self.referralBalance + refReward;
        let playerAddress = self.calculatePlayerAddress(msg.targetAddress);
        let init = initOf GemPlayer(msg.targetAddress, myAddress(), self.owner);
        let eggs = self.calculateEggBuy(investValue);
        send(SendParameters{
            to: playerAddress,
            value: gasForResponse, 
            mode: MODE_REGULAR,
            body: EggBuyResult{
                amount: investValue,
                eggs: eggs,
                referrer: msg.referrer 
            }.toCell(),
            code: init.code,
            data: init.data
        });
    }
    receive(msg: CollectDevFee) {
        require(sender() == self.owner, "Only owner can collect dev fee");
        require(self.devFeeBalance > 0, "No dev fee to collect");
        let amount = self.devFeeBalance;
        self.devFeeBalance = 0;
        send(SendParameters{
            to: self.owner,
            value: amount,
            mode: MODE_REGULAR,
            body: "DevFee".asComment() 
        });
    }
    receive(msg: WithdrawReferralRewards) {
        require(self.isPlayerContract(sender(), msg.ownerAddress), "Only player contract can call this");
        require(self.referralBalance >= msg.amount, "Insufficient referral balance");
        self.referralBalance = self.referralBalance - msg.amount;
        send(SendParameters{
            to: msg.to,
            value: msg.amount,
            mode: MODE_REGULAR,
            body: "Ref Reward".asComment() 
        });
    }
    receive() {
        let amount = context().value;
    }
    bounced(msg: Slice) {
        let op: Int = msg.loadUint(32); 
        let bounceValue = context().value;
        if (bounceValue > 0) {
        }
    }
    get fun getEggBuyAmount(amount: Int): Int {
        return self.calculateEggBuy(amount);
    }
    get fun getEggSellAmount(eggs: Int): Int {
        return self.calculateEggSell(eggs);
    }
    get fun getPlayerAddress(owner: Address): Address {
        return self.calculatePlayerAddress(owner);
    }
    get fun getRegistryInfo(): RegistryInfo {
        return RegistryInfo{
            marketEggs: self.marketEggs,
            balance: self.availableBalance(),
            devFeeBalance: self.devFeeBalance,
            referralBalance: self.referralBalance,
            eggsBuyPrice: self.calculateEggBuy(ONE_TON),
            owner: self.owner
        };
    }
}
