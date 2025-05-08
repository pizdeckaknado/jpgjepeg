import "@stdlib/deploy";
import "@stdlib/ownable";
import "./messages"; 
import "./player"; 
contract GemRegistry with Ownable, Deployable {
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
    fun isPlayerContract(addr: Address, ownerAddress: Address): Bool {
        if (addr == newAddress(0, 0)) {
            return false;
        }
        let calculatedAddress = getPlayerAddress(ownerAddress, myAddress(), self.owner);
        return calculatedAddress == addr;
    }
    fun availableBalance(): Int {
        return max(myBalance() - self.devFeeBalance - self.referralBalance, 0);
    }
    fun calculateEggBuy(eth: Int): Int {
        let availableBal = self.availableBalance();
        if (availableBal <= 0) {
            availableBal = 1;
        }
        return calculateTrade(eth, availableBal, self.marketEggs);
    }
    fun calculateEggSell(eggs: Int): Int {
        return calculateTrade(eggs, self.marketEggs, self.availableBalance());
    }
    fun processBuyMiners(targetAddress: Address, referrer: Address, value: Int, investAmount: Int): Address {
        require(value >= MIN_INVEST, "Minimum investment not met");
        require(investAmount <= value, "Investment amount exceeds sent value");
        require(investAmount >= MIN_INVEST, "Investment amount too small");
        let gasamount = value - investAmount;
        require(gasamount >= ton("0.1"), "Insufficient gas");
        let devFee = (investAmount * FEE_PERCENT) / 100;
        let investValue = investAmount - devFee;
        let refReward = (investValue * REFERRAL_PERCENT) / 100;
        require(investValue > 0, "Investment too small after fees");
        self.devFeeBalance += devFee;
        self.referralBalance += refReward;
        let init = initOf GemPlayer(targetAddress, myAddress(), self.owner);
        let playerAddress = contractAddress(init);
        let validReferrer = referrer;
        if (validReferrer == targetAddress) {
            validReferrer = null; 
        }
        let eggs = self.calculateEggBuy(investValue);
        send(SendParameters{
            to: playerAddress,
            value: gasamount,
            mode: SendDefaultMode,
            body: EggBuyResult{
                amount: investValue,
                eggs: eggs,
                referrer: validReferrer
            }.toCell(),
            code: init.code,
            data: init.data
        });
        return playerAddress;
    }
    receive(msg: UpdateMarketEggs) {
        let senderAddr = sender();
        require(self.isPlayerContract(senderAddr, msg.ownerAddress), "Only player contract can call this");
        let totalEggsSpent = msg.eggAmount * 5;
        let totalEggValue = self.calculateEggSell(totalEggsSpent);
        self.marketEggs += msg.eggAmount;
        let referralTonValue = (totalEggValue * HIRE_REFERRAL_PERCENT) / 100;
        let MIN_REFERRAL_TON: Int = ton("0.1");
        if (referralTonValue >= MIN_REFERRAL_TON && msg.referrer != null) {
            let referrerContractAddr = msg.referrer!!;
            self.referralBalance += referralTonValue;
            self.forward(referrerContractAddr, UpdateReferralReward{
                amount: referralTonValue,
                senderAddress: myAddress()
            }.toCell(), false, null);
        } else {
            self.forward(msg.ownerAddress, "Gas refund".asComment(), true, null);
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
        require(availableBal >= eggValue, "Insufficient balance for withdrawal");
        self.devFeeBalance += fee;
        self.marketEggs += msg.eggs;
        let equivalentEggs = self.calculateEggBuy(withdrawAmount);
        self.reply(SellEggsComplete{
            amount: withdrawAmount,
            equivalentEggs: equivalentEggs
        }.toCell());
        send(SendParameters{
            to: msg.ownerAddress,
            value: withdrawAmount,
            mode: SendDefaultMode,
            body: "TON.AG".asComment()
        });
    }
    receive(msg: BuyMiners) {
        self.processBuyMiners(context().sender, msg.referrer, context().value, msg.investAmount);
    }
    receive(msg: BuyMinersFor) {
        self.processBuyMiners(msg.targetAddress, msg.referrer, context().value, msg.investAmount);
    }
    receive(msg: CollectDevFee) {
        require(sender() == self.owner, "Only owner can collect dev fee");
        require(self.devFeeBalance > 0, "No dev fee to collect");
        let amount = self.devFeeBalance;
        self.devFeeBalance = 0;
        send(SendParameters{
            to: self.owner,
            value: amount,
            mode: SendRemainingValue,
            body: "DevFee".asComment() 
        });
    }
    receive(msg: WithdrawReferralRewards) {
        require(self.isPlayerContract(sender(), msg.ownerAddress), "Only player contract can call this");
        require(self.referralBalance >= msg.amount, "Insufficient referral balance");
        self.referralBalance -= msg.amount;
        send(SendParameters{
            to: msg.to,
            value: msg.amount,
            mode: SendRemainingValue,
            body: "Ref Reward".asComment() 
        });
    }
    get fun getPlayerAddress(owner: Address): Address {
        return getPlayerAddress(owner, myAddress(), self.owner);
    }
    get fun getRegistryInfo(): RegistryInfo {
        return RegistryInfo{
            marketEggs: self.marketEggs,
            balance: self.availableBalance(),
            devFeeBalance: self.devFeeBalance,
            referralBalance: self.referralBalance,
            owner: self.owner
        };
    }
}
