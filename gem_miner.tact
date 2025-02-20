import "@stdlib/deploy";
import "@stdlib/ownable";

// Constants
const ONE_TON: Int = 1000000000;  // 1 TON in nanotons
const MIN_INVEST: Int = ONE_TON;
const MIN_ACTION_INTERVAL: Int = 10800; // 3 hours in seconds
const INIT_MARKET_EGGS: Int = 108000000000;

// Referral system constants
const LEVEL1_PERCENT: Int = 75;        // 75% of the total referral reward
const LEVEL2_PERCENT: Int = 20;        // 20% of the total referral reward
const LEVEL3_PERCENT: Int = 5;         // 5% of the total referral reward
const REFERRAL_PERCENT: Int = 15;      // 15% for buyminers
const HIRE_REFERRAL_PERCENT: Int = 5;  // 5% for hireminers

const SEND_MODE_REGULAR: Int = 0;      // Regular message mode

const PSN: Int = 10000;
const PSNH: Int = 5000;
const EGGS_TO_HATCH_1MINERS: Int = 1080000;  // Corrected value from Solidity
const FEE_PERCENT: Int = 8;

// Health reduction constants
const WITHDRAWAL_THRESHOLD: Int = 300;    // 300% of the deposit

// Data structures
struct MaybeAddress {
    isSet: Bool;
    value: Address;
}

struct DepositInfo {
    amount: Int;       // Deposit amount
    miners: Int;       // Number of miners in this deposit
    withdrawn: Int;    // How much has been withdrawn
    health: Int;       // 2 - initial, 1 - after first reduction, 0 - after second reduction
}

struct Player {
    address: Address;
    deposits: map<Int, DepositInfo>;
}

struct UpdatePlayer {
    lastHatch: Int;
    claimedEggs: Int;
    upgradeCount: Int;
    referrer: MaybeAddress;
    level2Referrer: MaybeAddress;
    level3Referrer: MaybeAddress;
    referralRewards: Int;
    referralCount: Int;     // Added field to track the number of referrals
    totalDeposit: Int;
    totalMiners: Int;     // Total number of miners all time
    totalWithdrawn: Int;
    registrationTime: Int;  // Renamed lastActionTime to registrationTime
    depositCounter: Int;
}

struct PlayerMainStats {
    id: Int;
    lastHatch: Int;
    upgradeCount: Int;
    referralRewards: Int;
    totalMiners: Int;
    referralCount: Int;
    contractBalance: Int;  // Contract balance in nanotons
    marketEggs: Int;
    registrationTime: Int;
    totalDeposit: Int;
}

message(0x7361d09c) BuyMiners {
    referrerId: Int as uint32;  // Referrer ID (if 0, then no referrer)
}

message(0x7362d09c) SellGems {
}

message(0x7363d09c) ClaimRewards {
}

message(0x7364d09c) CollectDevFee {
}

message(0x7365d09c) HireMiners {
}

contract GemMiner with OwnableTransferable, Deployable {
    owner: Address;
    balance: Int;  // Contract balance in nanotons
    marketEggs: Int;
    players: map<Address, Player>;
    playerStats: map<Address, UpdatePlayer>;
    devFeeBalance: Int;  // Developer fee balance
    lastUserId: Int;              // Counter for generating IDs
    userIds: map<Int, Address>;   // Mapping from ID to Address
    addressToId: map<Address, Int>; // Reverse mapping from Address to ID

    init() {
        self.owner = sender();
        self.balance = 0;
        self.marketEggs = INIT_MARKET_EGGS;
        self.players = emptyMap();
        self.playerStats = emptyMap();
        self.devFeeBalance = 0;
        
        // Initialize system IDs
        self.lastUserId = 1;  // Start from 1 so that 0 is an invalid ID
        self.userIds = emptyMap();
        self.addressToId = emptyMap();
        
        // Create an ID for the contract owner
        self.userIds.set(1, self.owner);
        self.addressToId.set(self.owner, 1);
    }

    // Safe math functions
    fun safeAdd(a: Int, b: Int): Int {
        let c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    fun safeSub(a: Int, b: Int): Int {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    fun safeMul(a: Int, b: Int): Int {
        if (a == 0) {
            return 0;
        }
        let c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    fun safeDiv(a: Int, b: Int): Int {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }

    // Helper functions
    fun calculateTrade(rt: Int, rs: Int, bs: Int): Int {
        require(rt > 0 && rs > 0, "Invalid trade parameters");
        // (PSN*bs)/(PSNH+((PSN*rs+PSNH*rt)/rt))
        let numerator = self.safeMul(PSN, bs);
        let innerSum = self.safeAdd(
            self.safeMul(PSN, rs),
            self.safeMul(PSNH, rt)
        );
        let denominator = self.safeAdd(PSNH, self.safeDiv(innerSum, rt));
        return self.safeDiv(numerator, denominator);
    }

    fun calculateEggBuy(eth: Int): Int {
        return self.calculateTrade(eth, self.balance, self.marketEggs);
    }

    fun calculateEggSell(eggs: Int): Int {
        return self.calculateTrade(eggs, self.marketEggs, self.balance);
    }

    fun getEggsSinceLastHatch(player: Player): Int {
        let playerStats: UpdatePlayer? = self.playerStats.get(player.address);
        require(playerStats != null, "Player stats not found");
        let stats: UpdatePlayer = playerStats!!;
        
        // Calculate seconds passed since last hatch
        let secondsPassed = self.safeSub(now(), stats.lastHatch);
        let timeLimit = self.getTimeLimit(stats);
        secondsPassed = self.min(secondsPassed, timeLimit);
        
        // Return accumulated eggs
        return self.safeMul(secondsPassed, stats.totalMiners);
    }

    fun min(a: Int, b: Int): Int {
        if (a < b) {
            return a;
        }
        return b;
    }

    fun safeSend(to: Address, value: Int) {
        if (value > 0 && to != newAddress(0, 0)) {
            send(SendParameters{
                to: to,
                value: value,
                mode: SEND_MODE_REGULAR
            });
        }
    }

    // Helper functions to work with players
    fun getPlayerOrFail(addr: Address): Player {
        let player: Player? = self.players.get(addr);
        require(player != null, "Player not found");
        return player!!;
    }

    fun getOrCreatePlayer(addr: Address): Player {
        if (self.players.exists(addr)) {
            return self.getPlayerOrFail(addr);
        }
        // Initialize with empty map and save immediately
        let newPlayer = Player{
            address: addr,
            deposits: emptyMap()
        };
        // Save to storage before returning
        self.players.set(addr, newPlayer);
        return self.players.get(addr)!!;  // Get from storage to ensure consistency
    }

    fun getPlayerStatsOrFail(addr: Address): UpdatePlayer {
        let playerStats: UpdatePlayer? = self.playerStats.get(addr);
        require(playerStats != null, "Player stats not found");
        return playerStats!!;
    }

    fun getOrCreatePlayerStats(addr: Address): UpdatePlayer {
        let playerStats: UpdatePlayer? = self.playerStats.get(addr);
        if (playerStats != null) {
            return playerStats!!;
        }
        let newStats = UpdatePlayer{
            lastHatch: now(),
            claimedEggs: 0,
            upgradeCount: 0,
            referrer: MaybeAddress{
                isSet: false,
                value: newAddress(0, 0)
            },
            level2Referrer: MaybeAddress{
                isSet: false,
                value: newAddress(0, 0)
            },
            level3Referrer: MaybeAddress{
                isSet: false,
                value: newAddress(0, 0)
            },
            referralRewards: 0,
            referralCount: 0,    // Initialize referral counter
            totalDeposit: 0,
            totalMiners: 0,     // Total number of miners all time
            totalWithdrawn: 0,
            registrationTime: now(),  // Set registration time
            depositCounter: 0
        };
        self.playerStats.set(addr, newStats);
        return self.playerStats.get(addr)!!;
    }

    // Public getter to obtain main player stats
    get fun getPlayerMainStats(addr: Address): PlayerMainStats {
        let stats = self.getOrCreatePlayerStats(addr);
        let referralCount = self.getReferralCount(addr);
        
        return PlayerMainStats{
            id: self.getOrCreateUserId(addr),
            lastHatch: stats.lastHatch,
            upgradeCount: stats.upgradeCount,
            referralRewards: stats.referralRewards,
            totalMiners: stats.totalMiners,
            referralCount: referralCount,
            contractBalance: self.balance,
            marketEggs: self.marketEggs,
            registrationTime: stats.registrationTime,
            totalDeposit: stats.totalDeposit
        };
    }

    // Referral system helper functions
    fun processInitialReferral(player: Player, referrer: Address) {
        let playerStats = self.getOrCreatePlayerStats(player.address);
        
        // Check that the referrer is not already set
        if (playerStats.referrer.isSet) {
            return; // Skip if referrer already set
        }
        
        // Try to get referrer ID, if fails - use admin
        let referrerId: Int = 1; // Default to admin's ID
        let actualReferrer: Address = self.owner; // Default to admin
        
        // Validate referrer
        if (referrer != newAddress(0, 0)) {
            // Check if referrer exists in the system
            let refId = self.addressToId.get(referrer);
            if (refId != null && 
                refId!! > 0 && 
                refId!! <= self.lastUserId && 
                referrer != player.address) {
                referrerId = refId!!;
                actualReferrer = referrer;
            }
        }
        
        // Set first-level referrer
        playerStats.referrer = MaybeAddress{
            isSet: true,
            value: actualReferrer
        };
        
        // Get the referrer's stats and increment the direct referral counter
        let referrerStats = self.getOrCreatePlayerStats(actualReferrer);
        referrerStats.referralCount = referrerStats.referralCount + 1;
        self.playerStats.set(actualReferrer, referrerStats);
        
        // Try to set second-level referrer
        if (referrerStats.referrer.isSet) {
            let level2RefAddr = referrerStats.referrer.value;
            // Validate level 2 referrer
            if (level2RefAddr != newAddress(0, 0) && 
                level2RefAddr != self.owner && 
                level2RefAddr != player.address &&  // Prevent circular references
                level2RefAddr != actualReferrer &&  // Prevent circular references
                self.addressToId.get(level2RefAddr) != null) {
                
                playerStats.level2Referrer = MaybeAddress{
                    isSet: true,
                    value: level2RefAddr
                };
                
                // Try to set third-level referrer only if level 2 exists
                let level2Stats = self.getOrCreatePlayerStats(level2RefAddr);
                if (level2Stats.referrer.isSet) {
                    let level3RefAddr = level2Stats.referrer.value;
                    // Validate level 3 referrer
                    if (level3RefAddr != newAddress(0, 0) && 
                        level3RefAddr != self.owner && 
                        level3RefAddr != player.address &&  // Prevent circular references
                        level3RefAddr != actualReferrer &&  // Prevent circular references
                        level3RefAddr != level2RefAddr &&   // Prevent circular references
                        self.addressToId.get(level3RefAddr) != null) {
                        playerStats.level3Referrer = MaybeAddress{
                            isSet: true,
                            value: level3RefAddr
                        };
                    }
                }
            }
        }
        
        self.playerStats.set(player.address, playerStats);
    }

    // Unified referral reward distribution function
    fun distributeReferralReward(playerStats: UpdatePlayer, totalRefReward: Int) {
        // Calculate rewards for each level
        let l1p = self.safeMul(totalRefReward, LEVEL1_PERCENT) / 100; 
        let l2p = self.safeMul(totalRefReward, LEVEL2_PERCENT) / 100;
        let l3p = self.safeMul(totalRefReward, LEVEL3_PERCENT) / 100;
        
        // Initially assume all leftover is added to first level
        let level1Reward = l1p;
        let level2Reward = 0;
        let level3Reward = 0;

        // Check second level existence
        if (playerStats.level2Referrer.isSet && playerStats.level2Referrer.value != newAddress(0, 0)) {
            level2Reward = l2p; 
        } else {
            // No level 2? Add its share to level 1
            level1Reward = self.safeAdd(level1Reward, l2p);
        }

        // Check third level existence
        if (playerStats.level3Referrer.isSet && playerStats.level3Referrer.value != newAddress(0, 0)) {
            level3Reward = l3p;
        } else {
            // No level 3? Add its share to level 1
            level1Reward = self.safeAdd(level1Reward, l3p);
        }

        // Distribute rewards to each level

        // Level 1 (should always exist, even if it's admin)
        let level1RefAddr = playerStats.referrer.value; 
        if (level1RefAddr != newAddress(0, 0)) {
            let ref1Stats = self.getPlayerStatsOrFail(level1RefAddr);
            ref1Stats.referralRewards = self.safeAdd(ref1Stats.referralRewards, level1Reward);
            self.playerStats.set(level1RefAddr, ref1Stats);
        }

        // Level 2
        if (level2Reward > 0) {
            let level2RefAddr = playerStats.level2Referrer.value;
            let ref2Stats = self.getPlayerStatsOrFail(level2RefAddr);
            ref2Stats.referralRewards = self.safeAdd(ref2Stats.referralRewards, level2Reward);
            self.playerStats.set(level2RefAddr, ref2Stats);
        }

        // Level 3
        if (level3Reward > 0) {
            let level3RefAddr = playerStats.level3Referrer.value;
            let ref3Stats = self.getPlayerStatsOrFail(level3RefAddr);
            ref3Stats.referralRewards = self.safeAdd(ref3Stats.referralRewards, level3Reward);
            self.playerStats.set(level3RefAddr, ref3Stats);
        }
    }

    fun distributeReferralRewards(player: Player, amount: Int) {
        // Calculate the total referral reward
        let totalRefReward = self.safeMul(amount, REFERRAL_PERCENT) / 100;
        
        // Subtract the entire referral reward from the contract balance immediately
        self.balance = self.safeSub(self.balance, totalRefReward);
        
        // Get player's stats and distribute rewards
        let playerStats = self.getPlayerStatsOrFail(player.address);
        self.distributeReferralReward(playerStats, totalRefReward);
    }

    fun processReinvestReferralReward(player: Player, amount: Int) {
        // Calculate the total referral reward (5% for reinvest)
        let totalRefReward = self.safeMul(amount, HIRE_REFERRAL_PERCENT) / 100;
        
        // Subtract the entire referral reward from the contract balance immediately
        self.balance = self.safeSub(self.balance, totalRefReward);
        
        // Get player's stats and distribute rewards
        let playerStats = self.getPlayerStatsOrFail(player.address);
        self.distributeReferralReward(playerStats, totalRefReward);
    }

    // Deposit system functions
    fun getTimeLimit(playerStats: UpdatePlayer): Int {
        // Base time: 24 hours in seconds
        let baseTime: Int = 86400;  // 24 * 60 * 60
        
        // Additional time based on the number of upgrades
        let additionalTime: Int = 0;
        if (playerStats.upgradeCount >= 70) {
            additionalTime = baseTime * 5;  // 120 hours
        } else if (playerStats.upgradeCount >= 50) {
            additionalTime = baseTime * 4;  // 96 hours
        } else if (playerStats.upgradeCount >= 30) {
            additionalTime = baseTime * 3;  // 72 hours
        } else if (playerStats.upgradeCount >= 15) {
            additionalTime = baseTime * 2;  // 48 hours
        } else if (playerStats.upgradeCount >= 5) {
            additionalTime = baseTime;      // 24 hours
        }
        
        return baseTime + additionalTime;
    }

    fun processDeposit(player: Player, amount: Int, miners: Int) {
        let stats = self.getPlayerStatsOrFail(player.address);
        let depositId = stats.depositCounter;
        
        // Get fresh player data from storage
        let freshPlayer = self.getPlayerOrFail(player.address);
        
        // Create a new deposit
        let deposit = DepositInfo{
            amount: amount,
            miners: miners,
            withdrawn: 0,
            health: 2
        };
        
        // Add the deposit to the map
        freshPlayer.deposits.set(depositId, deposit);
        
        // Increment the deposit counter
        stats.depositCounter = stats.depositCounter + 1;
        
        // Update the total number of miners and lastHatch
        stats.totalMiners = self.safeAdd(stats.totalMiners, miners);
        stats.lastHatch = now();
        
        // Save updated data
        self.players.set(player.address, freshPlayer);
        self.playerStats.set(player.address, stats);
    }

    fun processHealthReduction(player: Player) {
        let stats = self.getPlayerStatsOrFail(player.address);
        require(stats.depositCounter > 0, "No deposits to process");
        let deposits = player.deposits;
        let i: Int = 0;
        let healthChanged: Bool = false;
        let totalMinersReduction: Int = 0;
        
        while (i < stats.depositCounter && !healthChanged) {
            let deposit = deposits.get(i);
            if (deposit != null && deposit!!.amount > 0) {
                let currentDeposit = deposit!!;
                let totalWithdrawn = self.safeDiv(self.safeMul(currentDeposit.withdrawn, 100), currentDeposit.amount);
                
                // First reduction of miners
                if (totalWithdrawn >= (WITHDRAWAL_THRESHOLD * 2) && currentDeposit.health == 2) {
                    let oldMiners = currentDeposit.miners;
                    currentDeposit.miners = self.safeDiv(self.safeMul(currentDeposit.miners, 5), 100); // -95% immediately
                    currentDeposit.health = 0;
                    
                    // Calculate the reduction in miners
                    let minersReduction = self.safeSub(oldMiners, currentDeposit.miners);
                    totalMinersReduction = self.safeAdd(totalMinersReduction, minersReduction);
                    
                    // Calculate and remove eggs for removed miners
                    let eggsToRemove = self.calculateEggsForMiners(minersReduction);
                    if (eggsToRemove > 0 && eggsToRemove <= self.marketEggs) {
                        self.marketEggs = self.safeSub(self.marketEggs, eggsToRemove);
                    }
                    
                    // Save the updated deposit
                    deposits.set(i, currentDeposit);
                    healthChanged = true;
                }
                // Normal first reduction
                else if (totalWithdrawn >= WITHDRAWAL_THRESHOLD && currentDeposit.health == 2) {
                    let oldMiners = currentDeposit.miners;
                    currentDeposit.miners = self.safeDiv(self.safeMul(currentDeposit.miners, 10), 100); // -90%
                    currentDeposit.health = 1;
                    
                    // Calculate the reduction in miners
                    let minersReduction = self.safeSub(oldMiners, currentDeposit.miners);
                    totalMinersReduction = self.safeAdd(totalMinersReduction, minersReduction);
                    
                    // Calculate and remove eggs for removed miners
                    let eggsToRemove = self.calculateEggsForMiners(minersReduction);
                    if (eggsToRemove > 0 && eggsToRemove <= self.marketEggs) {
                        self.marketEggs = self.safeSub(self.marketEggs, eggsToRemove);
                    }
                    
                    // Save the updated deposit
                    deposits.set(i, currentDeposit);
                    healthChanged = true;
                }
                
                // Second reduction of miners
                if (totalWithdrawn >= (WITHDRAWAL_THRESHOLD * 2) && currentDeposit.health == 1) {
                    let oldMiners = currentDeposit.miners;
                    currentDeposit.miners = self.safeDiv(self.safeMul(currentDeposit.miners, 50), 100); // -50%
                    currentDeposit.health = 0;
                    
                    // Calculate the reduction in miners
                    let minersReduction = self.safeSub(oldMiners, currentDeposit.miners);
                    totalMinersReduction = self.safeAdd(totalMinersReduction, minersReduction);
                    
                    // Calculate and remove eggs for removed miners
                    let eggsToRemove = self.calculateEggsForMiners(minersReduction);
                    if (eggsToRemove > 0 && eggsToRemove <= self.marketEggs) {
                        self.marketEggs = self.safeSub(self.marketEggs, eggsToRemove);
                    }
                    
                    // Save the updated deposit
                    deposits.set(i, currentDeposit);
                    healthChanged = true;
                }
            }
            i = i + 1;
        }
        
        // Update total miners count
        if (totalMinersReduction > 0) {
            stats.totalMiners = self.safeSub(stats.totalMiners, totalMinersReduction);
        }
        
        // Save updated data
        self.players.set(player.address, player);
        self.playerStats.set(player.address, stats);
        
        // If health has changed, try to merge "dead" deposits
        if (healthChanged) {
            self.mergeDeadDeposits(player);
        }
    }

    fun mergeDeadDeposits(player: Player) {
        let stats = self.getPlayerStatsOrFail(player.address);
        let deposits = player.deposits;
        
        // If only one deposit exists, do not merge it
        if (stats.depositCounter <= 1) {
            return;
        }
        
        // Find the last active deposit
        let lastActiveIndex: Int = -1;
        let i: Int = stats.depositCounter - 1;
        let found: Bool = false;
        while (i >= 0 && !found) {
            let deposit = deposits.get(i);
            if (deposit != null && deposit!!.health > 0) {
                lastActiveIndex = i;
                found = true;
            }
            i = i - 1;
        }
        
        // If an active deposit is found, transfer miners from "dead" deposits into it
        if (lastActiveIndex >= 0) {
            let lastActiveDeposit = deposits.get(lastActiveIndex)!!;
            let newDeposits: map<Int, DepositInfo> = emptyMap();
            let newIndex: Int = 0;
            
            // Loop through all deposits
            i = 0;
            while (i < stats.depositCounter) {
                let deposit = deposits.get(i);
                if (deposit != null) {
                    if (deposit!!.health == 0 && i != lastActiveIndex) {
                        // Transfer miners to the last active deposit
                        lastActiveDeposit.miners = self.safeAdd(lastActiveDeposit.miners, deposit!!.miners);
                    } else {
                        // Save the deposit
                        newDeposits.set(newIndex, deposit!!);
                        newIndex = newIndex + 1;
                    }
                }
                i = i + 1;
            }
            
            // Update the last active deposit with the new miner count
            newDeposits.set(lastActiveIndex, lastActiveDeposit);
            
            // Update player's data
            player.deposits = newDeposits;
            stats.depositCounter = newIndex;
            
            // Save updated data
            self.players.set(player.address, player);
            self.playerStats.set(player.address, stats);
        }
    }

    fun processWithdrawal(player: Player, amount: Int) {
        require(amount > 0, "Amount must be positive");
        require(amount <= self.balance, "Insufficient contract liquidity");
        let stats = self.getPlayerStatsOrFail(player.address);
        
        // Check if the player has sufficient funds
        let eggsValue = self.calculateEggSell(self.getEggsSinceLastHatch(player));
        require(eggsValue > 0, "No eggs to sell");
        let availableBalance = self.safeAdd(stats.totalWithdrawn, eggsValue);
        require(amount <= availableBalance, "Insufficient player balance");
        
        let remaining = amount;
        let i: Int = 0;
        let totalMinersReduction: Int = 0;
        
        while (i < stats.depositCounter && remaining > 0) {
            let depositValue: DepositInfo? = player.deposits.get(i);
            
            if (depositValue != null) {
                let deposit = depositValue!!;
                if (deposit.amount > 0 && deposit.health > 0) {
                    // Continue withdrawing from the current deposit until limit is reached or remaining becomes 0
                    let canContinue: Bool = true;
                    while (remaining > 0 && deposit.health > 0 && canContinue) {
                        // Determine the current threshold based on health
                        let currentThreshold: Int = 0;
                        if (deposit.health == 2) {
                            currentThreshold = WITHDRAWAL_THRESHOLD; // 300%
                        } else if (deposit.health == 1) {
                            currentThreshold = WITHDRAWAL_THRESHOLD * 2; // 600%
                        }
                        
                        let allowedWithdraw = self.safeDiv(self.safeMul(deposit.amount, currentThreshold), 100);
                        let availableToWithdraw = self.safeSub(allowedWithdraw, deposit.withdrawn);
                        
                        if (availableToWithdraw <= 0) {
                            canContinue = false;
                        } else {
                            let maxWithdraw = self.min(remaining, availableToWithdraw);
                            
                            if (maxWithdraw > 0) {
                                // Update withdrawn before calculating new health
                                deposit.withdrawn = self.safeAdd(deposit.withdrawn, maxWithdraw);
                                remaining = self.safeSub(remaining, maxWithdraw);
                                
                                // Check threshold and reduce miners if needed
                                let totalWithdrawn = self.safeDiv(self.safeMul(deposit.withdrawn, 100), deposit.amount);
                                
                                if (totalWithdrawn >= WITHDRAWAL_THRESHOLD && deposit.health == 2) {
                                    let oldMiners = deposit.miners;
                                    deposit.miners = self.safeDiv(self.safeMul(deposit.miners, 10), 100); // -90%
                                    deposit.health = 1;
                                    
                                    let minersReduction = self.safeSub(oldMiners, deposit.miners);
                                    totalMinersReduction = self.safeAdd(totalMinersReduction, minersReduction);
                                }
                                
                                if (totalWithdrawn >= (WITHDRAWAL_THRESHOLD * 2) && deposit.health == 1) {
                                    let oldMiners = deposit.miners;
                                    deposit.miners = self.safeDiv(self.safeMul(deposit.miners, 50), 100); // -50%
                                    deposit.health = 0;
                                    
                                    let minersReduction = self.safeSub(oldMiners, deposit.miners);
                                    totalMinersReduction = self.safeAdd(totalMinersReduction, minersReduction);
                                    
                                    canContinue = false; // Deposit "dead", move to next
                                }
                                
                                // Save updated deposit
                                player.deposits.set(i, deposit);
                            } else {
                                canContinue = false;
                            }
                        }
                    }
                }
            }
            i = i + 1; // Move to next deposit only if current is fully exhausted or "dead"
        }
        
        // Update total withdrawn amount
        let actualWithdrawn = self.safeSub(amount, remaining);
        require(actualWithdrawn > 0, "Nothing to withdraw");
        
        // Update player's statistics
        stats.totalWithdrawn = self.safeAdd(stats.totalWithdrawn, actualWithdrawn);
        if (totalMinersReduction > 0) {
            stats.totalMiners = self.safeSub(stats.totalMiners, totalMinersReduction);
        }
        
        // Save updated statistics
        self.playerStats.set(player.address, stats);
        
        // Check if merging of deposits is needed
        self.mergeDeadDeposits(player);
    }

    // Core functions
    fun withdraw(to: Address, amount: Int) {
        send(SendParameters{
            to: to,
            value: amount,
            mode: SEND_MODE_REGULAR
        });
    }

    receive(msg: BuyMiners) {
        let sender = context().sender;
        let value = context().value;
        require(value >= MIN_INVEST, "Minimum investment not met");
        
        // Calculate developer fee in TON
        let devFee = self.safeDiv(self.safeMul(value, FEE_PERCENT), 100);
        let investValue = self.safeSub(value, devFee);
        
        // Update contract balance (excluding fee)
        self.balance = self.safeAdd(self.balance, investValue);
        
        // Add fee to developer fee balance
        self.devFeeBalance = self.safeAdd(self.devFeeBalance, devFee);
        
        // Get referrer address by ID
        let referrerAddress: Address = self.owner; // Default to contract owner
        if (msg.referrerId > 0) {
            require(msg.referrerId <= self.lastUserId, "Invalid referrer ID");
            let refAddr = self.getUserAddress(msg.referrerId);
            require(refAddr != null, "Referrer not found");
            require(refAddr!! != sender, "Cannot refer yourself");
            referrerAddress = refAddr!!;
        }
        
        // Get or create player and their stats
        let player = self.getOrCreatePlayer(sender);
        let stats = self.getOrCreatePlayerStats(sender);
        
        // Check action interval if not the first deposit
        if (stats.depositCounter > 0) {
            require(self.safeSub(now(), stats.lastHatch) >= MIN_ACTION_INTERVAL, "Action too frequent");
        }
        
        // Process referral system on first deposit
        if (stats.depositCounter == 0) {
            self.processInitialReferral(player, referrerAddress);
            // Get fresh data after referral processing
            stats = self.playerStats.get(sender)!!;
        }
        
        // Distribute referral rewards on every deposit (using investValue instead of value)
        if (stats.referrer.isSet) {
            self.distributeReferralRewards(player, investValue);
            stats = self.playerStats.get(sender)!!;
        }
        
        // Calculate eggs for purchase (using investValue)
        let eggs = self.calculateEggBuy(investValue);
        require(eggs > 0, "Not enough eggs");
        
        // Convert eggs to miners with rounding up
        let miners = self.safeDiv(
            self.safeAdd(eggs, EGGS_TO_HATCH_1MINERS - 1),
            EGGS_TO_HATCH_1MINERS
        );
        require(miners > 0, "Not enough miners");
        
        // Add eggs to player's claimed eggs instead of market
        stats.claimedEggs = self.safeAdd(stats.claimedEggs, eggs);
        
      
        // Create a new deposit (using investValue)
        self.processDeposit(player, investValue, miners);
        
        // Update player's statistics
        stats.totalDeposit = self.safeAdd(stats.totalDeposit, investValue);
        self.playerStats.set(sender, stats);
    }

    receive(msg: HireMiners) {
        let sender = context().sender;
        let player = self.getPlayerOrFail(sender);
        let stats = self.getPlayerStatsOrFail(sender);
        require(self.safeSub(now(), stats.lastHatch) >= MIN_ACTION_INTERVAL, "Action too frequent");
        
        // Get eggs to hire
        let eggsUsed = self.getEggsSinceLastHatch(player);
        require(eggsUsed > 0, "No eggs to hire");
        
        // Add claimed eggs
        eggsUsed = self.safeAdd(eggsUsed, stats.claimedEggs);
        
        // Calculate TON equivalent for referral reward
        let reinvestValue = self.calculateEggSell(eggsUsed);
        
        // Calculate new miners
        let newMiners = self.safeDiv(eggsUsed, EGGS_TO_HATCH_1MINERS);
        require(newMiners > 0, "Not enough eggs for new miners");
        
        // Update market eggs (only 20% like in BakedPizza)
        self.marketEggs = self.safeAdd(self.marketEggs, self.safeDiv(eggsUsed, 5));
        
        // Process referral rewards using TON equivalent
        if (stats.referrer.isSet) {
            self.processReinvestReferralReward(player, reinvestValue);
        }
        
        // Reset claimed eggs and update last hatch
        stats.claimedEggs = 0;
        stats.lastHatch = now();
        
        // Add new miners to total
        stats.totalMiners = self.safeAdd(stats.totalMiners, newMiners);
        
        // Increment upgrade count
        stats.upgradeCount = stats.upgradeCount + 1;
        
        // Save updated stats
        self.playerStats.set(sender, stats);
    }

    receive(msg: SellGems) {
        let sender = context().sender;
        let player = self.getPlayerOrFail(sender);
        let stats = self.getPlayerStatsOrFail(sender);
        
        // Check action interval
        require(self.safeSub(now(), stats.lastHatch) >= MIN_ACTION_INTERVAL, "Action too frequent");
        
        // Get eggs to sell
        let eggsUsed = self.getEggsSinceLastHatch(player);
        require(eggsUsed > 0, "No eggs to sell");
        
        // Add claimed eggs
        eggsUsed = self.safeAdd(eggsUsed, stats.claimedEggs);
        
        // Calculate egg value
        let amount = self.calculateEggSell(eggsUsed);
        require(amount > 0, "Nothing to sell");
        
        // Add all sold eggs to market 
        self.marketEggs = self.safeAdd(self.marketEggs, eggsUsed);
        
        // Calculate and process fee
        let fee = self.safeDiv(self.safeMul(amount, FEE_PERCENT), 100);
        let withdrawAmount = self.safeSub(amount, fee);
        
        // Process withdrawal
        self.processWithdrawal(player, withdrawAmount);
        
        self.devFeeBalance = self.safeAdd(self.devFeeBalance, fee);
        
        // Update contract balance
        self.balance = self.safeSub(self.balance, self.safeSub(amount, fee));
        
        // Reset claimedEggs and update lastHatch
        stats.claimedEggs = 0;
        stats.lastHatch = now();
        
        // Save updated stats
        self.playerStats.set(sender, stats);
        
        // Send TON to player
        self.withdraw(sender, withdrawAmount);
    }

    receive(msg: ClaimRewards) {
        let sender = context().sender;
        let player = self.getPlayerOrFail(sender);
        let stats = self.getPlayerStatsOrFail(sender);
        
        // Check if rewards exist
        require(stats.referralRewards > 0, "No rewards to claim");
        
        let amount = stats.referralRewards;
        
        // Reset rewards in stats
        stats.referralRewards = 0;
        self.playerStats.set(sender, stats);
        
        // Send TON to player
        send(SendParameters{
            to: sender,
            value: amount,
            mode: SEND_MODE_REGULAR
        });
    }

    receive(msg: CollectDevFee) {
        // Ensure only the owner can call this
        require(sender() == self.owner, "Only owner can collect dev fee");
        
        // Check if there is any fee to collect
        require(self.devFeeBalance > 0, "No dev fee to collect");
        
        // Remember the fee amount
        let amount = self.devFeeBalance;
        
        // Reset fee balance
        self.devFeeBalance = 0;
        
        // Send fee to the owner
        send(SendParameters{
            to: self.owner,
            value: amount,
            mode: SEND_MODE_REGULAR
        });
    }

    // Function to count the number of referrals
    fun getReferralCount(addr: Address): Int {
        let stats = self.getOrCreatePlayerStats(addr);
        return stats.referralCount;
    }

    // Get or create a user ID for the given address - O(1) operation
    fun getOrCreateUserId(addr: Address): Int {
        // Check if ID exists in reverse mapping
        let existingId: Int? = self.addressToId.get(addr);
        if (existingId != null) {
            return existingId!!;
        }
        
        // If not found, create a new one
        self.lastUserId = self.lastUserId + 1;
        self.userIds.set(self.lastUserId, addr);
        self.addressToId.set(addr, self.lastUserId);
        return self.lastUserId;
    }

    // Get address by ID
    fun getUserAddress(id: Int): Address? {
        require(id > 0, "ID must be positive");
        require(id <= self.lastUserId, "ID does not exist");
        return self.userIds.get(id);
    }

    fun emptyMaybeAddress(): MaybeAddress {
        return MaybeAddress{
            isSet: false,
            value: newAddress(0, 0)
        };
    }

    // Function to calculate the number of eggs for a given number of miners based on the current rate
    fun calculateEggsForMiners(miners: Int): Int {
        return self.safeMul(miners, EGGS_TO_HATCH_1MINERS);
    }
} 
