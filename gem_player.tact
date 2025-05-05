import "@stdlib/deploy";
import "./messages"; 
contract GemPlayer with Deployable {
    owner: Address;           
    registry: Address;        
    registryOwner: Address;   
    lastHatch: Int;
    upgradeCount: Int;
    referrer: Address?;   
    referralRewards: Int;
    totalDeposit: Int;
    totalMiners: Int;
    totalWithdrawn: Int;
    registrationTime: Int;
    depositCounter: Int;
    deposits: map<Int, DepositInfo>;
    init(owner: Address, registry: Address, registryOwner: Address) {
        self.owner = owner;
        self.registry = registry;
        self.registryOwner = registryOwner;
        self.lastHatch = now();
        self.upgradeCount = 0;
        self.referrer = null;
        self.referralRewards = 0;
        self.totalDeposit = 0;
        self.totalMiners = 0;
        self.totalWithdrawn = 0;
        self.registrationTime = now();
        self.depositCounter = 0;
        self.deposits = null;
    }
    fun min(a: Int, b: Int): Int {
        if (a < b) {
            return a;
        }
        return b;
    }
    fun getTimeLimit(): Int {
        let baseTime: Int = 86400;  
        let additionalTime: Int = 0;
        if (self.upgradeCount >= 70) {
            additionalTime = baseTime * 5;  
        } else if (self.upgradeCount >= 50) {
            additionalTime = baseTime * 4;  
        } else if (self.upgradeCount >= 30) {
            additionalTime = baseTime * 3;  
        } else if (self.upgradeCount >= 15) {
            additionalTime = baseTime * 2;  
        } else if (self.upgradeCount >= 5) {
            additionalTime = baseTime;      
        }
        return baseTime + additionalTime;
    }
    fun getEggsSinceLastHatch(): Int {
        let secondsPassed = now() - self.lastHatch;
        let timeLimit = self.getTimeLimit();
        secondsPassed = self.min(secondsPassed, timeLimit);
        return secondsPassed * self.totalMiners;
    }
    fun processDeposit(amount: Int, miners: Int) {
        self.totalDeposit += amount;
        let depositId = self.depositCounter;
        let deposit = DepositInfo{
            amount: amount,
            miners: miners,
            withdrawn: 0,
            health: 2
        };
        self.deposits.set(depositId, deposit);
        self.depositCounter += 1;
        self.totalMiners += miners;
        self.lastHatch = now();
    }
    fun processHealthReduction() {
        require(self.depositCounter > 0, "No deposits to process");
        let i: Int = 0;
        let healthChanged: Bool = false;
        let totalMinersReduction: Int = 0;
        while (i < self.depositCounter && !healthChanged) {
            let deposit = self.deposits.get(i);
            if (deposit != null && deposit!!.amount > 0 && deposit!!.health > 0) {
                let currentDeposit = deposit!!;
                let totalWithdrawn = (currentDeposit.withdrawn * 100) / currentDeposit.amount;
                if (totalWithdrawn >= (WITHDRAWAL_THRESHOLD * 2) && currentDeposit.health == 2) {
                    let oldMiners = currentDeposit.miners;
                    currentDeposit.miners = (currentDeposit.miners * 10) / 100; 
                    currentDeposit.health = 0;
                    let minersReduction = oldMiners - currentDeposit.miners;
                    totalMinersReduction += minersReduction;
                    self.deposits.set(i, currentDeposit);
                    healthChanged = true;
                }
                else if (totalWithdrawn >= WITHDRAWAL_THRESHOLD && currentDeposit.health == 2) {
                    let oldMiners = currentDeposit.miners;
                    currentDeposit.miners = (currentDeposit.miners * 20) / 100; 
                    currentDeposit.health = 1;
                    let minersReduction = oldMiners - currentDeposit.miners;
                    totalMinersReduction += minersReduction;
                    self.deposits.set(i, currentDeposit);
                    healthChanged = true;
                }
                else if (totalWithdrawn >= (WITHDRAWAL_THRESHOLD * 2) && currentDeposit.health == 1) {
                    let oldMiners = currentDeposit.miners;
                    currentDeposit.miners = (currentDeposit.miners * 60) / 100; 
                    currentDeposit.health = 0;
                    let minersReduction = oldMiners - currentDeposit.miners;
                    totalMinersReduction += minersReduction;
                    self.deposits.set(i, currentDeposit);
                    healthChanged = true;
                }
            }
            i += 1;
        }
        if (totalMinersReduction > 0) {
            self.totalMiners -= totalMinersReduction;
        }
        if (healthChanged) {
            self.mergeDeadDeposits();
        }
    }
    fun mergeDeadDeposits() {
        if (self.depositCounter <= 1) {
            return;
        }
        let lastActiveIndex: Int = -1;
        let i: Int = self.depositCounter - 1;
        let found: Bool = false;
        while (i >= 0 && !found) {
            let deposit = self.deposits.get(i);
            if (deposit != null && deposit!!.amount > 0) {
                lastActiveIndex = i;
                found = true;
            }
            i -= 1;
        }
        if (lastActiveIndex >= 0) {
            let lastActiveDeposit = self.deposits.get(lastActiveIndex)!!;
            let newDeposits: map<Int, DepositInfo> = null; 
            let newIndex: Int = 0;
            let lastActiveNewIndex: Int = -1;
            let totalRemovedAmount: Int = 0;  
            i = 0;
            while (i < self.depositCounter) {
                let deposit = self.deposits.get(i);
                if (deposit != null) {
                    if (deposit!!.health == 0 && i != lastActiveIndex) {
                        lastActiveDeposit.miners = lastActiveDeposit.miners + deposit!!.miners;
                        totalRemovedAmount = totalRemovedAmount + deposit!!.amount;
                        if (deposit!!.withdrawn > 0 && self.totalWithdrawn >= deposit!!.withdrawn) {
                            self.totalWithdrawn -= deposit!!.withdrawn;
                        }
                    } else {
                        if (i == lastActiveIndex) {
                            lastActiveNewIndex = newIndex;
                        }
                        newDeposits.set(newIndex, deposit!!);
                        newIndex = newIndex + 1;
                    }
                }
                i += 1;
            }
            if (lastActiveNewIndex >= 0) {
                newDeposits.set(lastActiveNewIndex, lastActiveDeposit);
            }
            if (totalRemovedAmount > 0 && self.totalDeposit >= totalRemovedAmount) {
                self.totalDeposit -= totalRemovedAmount;
            }
            self.deposits = newDeposits;
            self.depositCounter = newIndex;
        }
    }
receive(msg: EggBuyResult) {
    require(sender() == self.registry, "Only registry can send this message");
    let eggAmount = msg.eggs;
    self.processDeposit(msg.amount, eggAmount / EGGS_TO_HATCH_1MINERS);
    if (self.depositCounter == 1) {
        self.processInitialReferral(msg.referrer);
    }
    let refReward = (msg.amount * REFERRAL_PERCENT) / 100;
    if (self.referrer != null) {
        self.distributeReferralRewards(refReward);
    }
}
    fun processInitialReferral(referrer: Address) {
        if (self.referrer != null) {
            return; 
        }
        let adminPlayerAddress = getPlayerAddress(self.registryOwner, self.registry, self.registryOwner);  
        if (referrer == newAddress(0, 0) || referrer == self.owner) {
            self.referrer = adminPlayerAddress;
        } else {
            let referrerPlayerAddress = getPlayerAddress(referrer, self.registry, self.registryOwner);  
            self.referrer = referrerPlayerAddress;
        }
    }
    receive(msg: SellGems) {
        require(sender() == self.owner, "Only owner can call this");
        require((now() - self.lastHatch) >= MIN_ACTION_INTERVAL, "Action too frequent");
        require(context().value >= ton("0.1"), "Insufficient gas");
        let eggsUsed = self.getEggsSinceLastHatch();
        require(eggsUsed > 0, "No eggs to sell");
        self.forward(self.registry, SellEggsAndWithdraw{
            eggs: eggsUsed,
            ownerAddress: self.owner, 
            playerOwner: self.owner  
        }.toCell(), false);
        self.lastHatch = now();
    }
receive(msg: HireMiners) {
    require(sender() == self.owner, "Only owner can hire miners");
    require((now() - self.lastHatch) >= MIN_ACTION_INTERVAL, "Action too frequent");
    require(context().value >= ton("0.1"), "Insufficient gas");
    let eggs = self.getEggsSinceLastHatch();
    require(eggs > 0, "No eggs to hire miners with");
    let newMiners = eggs / EGGS_TO_HATCH_1MINERS;
    self.lastHatch = now();
    self.totalMiners += newMiners;
    self.upgradeCount += 1;
    let eggAmount = eggs / 5;
    self.forward(self.registry, UpdateMarketEggs{
        eggAmount: eggAmount,
        ownerAddress: self.owner,
        referrer: self.referrer
    }.toCell(), false);
    let currentBalance = myBalance();
    let threshold: Int = ton("0.5");
    let reserveAmount: Int = ton("0.2");
    if (currentBalance > threshold) {
        let excessAmount = currentBalance - reserveAmount;
        send(SendParameters{
            to: self.registry,
            value: excessAmount,
            mode: SendDefaultMode,
            body: "ExcessBalance".asComment()
        });
    }
}
    fun distributeReferralRewards(totalRefReward: Int) {
        if (self.referrer == null) {
            return;
        }
        let MIN_REWARD_VALUE: Int = ton("0.1");
        if (totalRefReward < MIN_REWARD_VALUE) {
            return; 
        }
      let msg = UpdateReferralReward{
        amount: totalRefReward,
        senderAddress: self.owner
    }.toCell();
    self.forward(self.referrer!!, msg, false);
    }
    receive(msg: ClaimRewards) {
        require(sender() == self.owner, "Only owner can claim rewards");
        require(self.referralRewards > 0, "No rewards to claim");
        let amount = self.referralRewards;
        self.referralRewards = 0;
        self.forward(self.registry, WithdrawReferralRewards{
            amount: amount,
            to: self.owner, 
            ownerAddress: self.owner 
        }.toCell(), false);
    }
    receive() {
        let amount = context().value;
        if (amount < MIN_DEPOSIT) {
            return; 
        }
        send(SendParameters{
            to: self.registry,
            value: amount,
            mode: SendDefaultMode
        });
    }
receive(msg: UpdateReferralReward) {
    let senderAddr = sender();
    let senderPlayerAddress = getPlayerAddress(msg.senderAddress, self.registry, self.registryOwner);  
    require(senderAddr == self.registry || senderAddr == senderPlayerAddress, 
            "Unauthorized sender for referral update");
    let MIN_REWARD_VALUE: Int = ton("0.1");
    let adminPlayerAddress = getPlayerAddress(self.registryOwner, self.registry, self.registryOwner);  
    if (self.owner == self.registryOwner) {
        self.referralRewards += msg.amount;
        return;
    }
    if (self.referrer == adminPlayerAddress) {
        self.referralRewards += msg.amount;
        return;
    }
    let myReward = (msg.amount * LEVEL1_PERCENT) / 100;
    let nextLevelAmount = msg.amount - myReward;
    self.referralRewards += myReward;
    if (nextLevelAmount >= MIN_REWARD_VALUE && self.referrer != null) {
        let nextMsg = ProcessNextLevelReward{
            amount: nextLevelAmount,
            senderAddress: self.owner
        }.toCell();
        self.forward(self.referrer!!, nextMsg, false);
    } else {
        self.referralRewards += nextLevelAmount;
    }
}
receive(msg: ProcessNextLevelReward) {
    let senderAddr = sender();
    let senderPlayerAddress = getPlayerAddress(msg.senderAddress, self.registry, self.registryOwner);  
    require(senderAddr == senderPlayerAddress, "Unauthorized sender for next level reward");
    let MIN_REWARD_VALUE: Int = ton("0.1");
    let adminPlayerAddress = getPlayerAddress(self.registryOwner, self.registry, self.registryOwner);  
    if (self.referrer == adminPlayerAddress) {
        self.referralRewards += msg.amount;
        return;
    }
    let myReward = (msg.amount * 80) / 100;
    let nextLevelAmount = msg.amount - myReward;
    self.referralRewards += myReward;
    if (nextLevelAmount >= MIN_REWARD_VALUE && self.referrer != null) {
        self.forward(self.referrer!!, ProcessLastLevelReward{
            amount: nextLevelAmount,
            senderAddress: self.owner
        }.toCell(), false);
    } else {
        self.referralRewards += nextLevelAmount;
    }
}
receive(msg: ProcessLastLevelReward) {
    let senderAddr = sender();
    let senderPlayerAddress = getPlayerAddress(msg.senderAddress, self.registry, self.registryOwner);  
    require(senderAddr == senderPlayerAddress, "Unauthorized sender for last level reward");
    self.referralRewards += msg.amount;
}
    receive(msg: SellEggsComplete) {
        require(sender() == self.registry, "Only registry can send this message");
        let equivalentEggs = msg.equivalentEggs;
        let equivalentMiners = equivalentEggs / EGGS_TO_HATCH_1MINERS;
        self.totalWithdrawn += msg.amount;
        let minersReduced = false;
        let i: Int = 0;
        while (i < self.depositCounter && !minersReduced) {
            let deposit = self.deposits.get(i);
            if (deposit != null && deposit!!.amount > 0) {
                let currentDeposit = deposit!!;
                let newWithdrawn = currentDeposit.withdrawn + msg.amount;
                let depositWithdrawRatio = (newWithdrawn * 100) / currentDeposit.amount;
                let penaltyFactor = 0;
                if (depositWithdrawRatio < 150) {
                    penaltyFactor = 7 + (depositWithdrawRatio * 8) / 150;
                } else if (depositWithdrawRatio < 300) {
                    let excess = depositWithdrawRatio - 150;
                    penaltyFactor = 15 + (excess * 20) / 150;
                } else if (depositWithdrawRatio <= 450) {
                    let excess = depositWithdrawRatio - 300;
                    penaltyFactor = 35 + (excess * 35) / 150;
                } else if (depositWithdrawRatio <= 600) {
                    let excess = depositWithdrawRatio - 450;
                    penaltyFactor = 70 + (excess * 25) / 150;
                } else {
                    penaltyFactor = 95;
                }
                currentDeposit.withdrawn = newWithdrawn;
                if (penaltyFactor > 0 && currentDeposit.miners > 1) {
                    let oldMiners = currentDeposit.miners;
                    let minersToReduce = (equivalentMiners * penaltyFactor) / 100;
                    if (currentDeposit.miners > minersToReduce) {
                        currentDeposit.miners = currentDeposit.miners - minersToReduce;
                    } else if (currentDeposit.miners > 1) {
                        currentDeposit.miners = 1;
                    }
                    let actualReduction = oldMiners - currentDeposit.miners;
                    self.totalMiners -= actualReduction;
                    minersReduced = true;
                }
                self.deposits.set(i, currentDeposit);
            }
            i += 1;
        }
        if (self.totalDeposit > 0) {
            let withdrawalPercentage = (self.totalWithdrawn * 100) / self.totalDeposit;
            if (withdrawalPercentage > WITHDRAWAL_THRESHOLD) {
                self.processHealthReduction();
            }
        }
        self.lastHatch = now();
    }
    get fun getPlayerStats(): UpdatePlayer {
        return UpdatePlayer{
            lastHatch: self.lastHatch,
            upgradeCount: self.upgradeCount,
            referrer: self.referrer,
            referralRewards: self.referralRewards,
            totalDeposit: self.totalDeposit,
            totalMiners: self.totalMiners,
            totalWithdrawn: self.totalWithdrawn,
            registrationTime: self.registrationTime,
            depositCounter: self.depositCounter
        };
    }
    get fun getDeposit(id: Int): DepositInfo? {
        return self.deposits.get(id);
    }
    get fun getDeposits(): map<Int, DepositInfo> {
        return self.deposits;
    }
}
