                               K I N D O R A   (KNR)
              Complete Token + Charity Vault Architecture (ASCII Flow Style)
                     Full Explanation Exactly Matching Smart Contracts



INTRODUCTION
Kindora (KNR) is a charity-driven token ecosystem deployed on Binance Smart Chain.
It is built from two smart contracts that operate together as one system:

1. KNR Token Contract – manages tokenomics, fees, burn, liquidity, SwapBack, anti-whale limits.
2. Charity Vault Contract – receives BNB generated from the token, stores or forwards it,
   and can lock the charity destination for long-term trust.

This README uses a single ASCII flowchart style throughout, matching exactly the
behavior defined in the Solidity code.



===============================================================================
TOKENOMICS FLOW (5% ON BUY/SELL)

                               BUY or SELL
                                   │
                                   ▼
                             5% TAX APPLIED
                   ┌───────────────┼────────────────┐
                   │               │                │
                   ▼               ▼                ▼
                1% BURN        1% LIQUIDITY      3% CHARITY
          (sent to dead)     (used in LP)       (swapped to BNB)



===============================================================================
SUPPLY AND BASICS

- Total supply: 10,000,000 KNR
- Decimals: 18
- All tokens minted to owner at deployment
- No minting function → supply is permanently fixed

                                DEPLOYMENT
                                   │
                                   ▼
                           OWNER RECEIVES SUPPLY
                                   │
                                   ▼
                           SUPPLY FIXED FOREVER



===============================================================================
DEX ROUTER INTEGRATION

The contract creates its liquidity pair on deployment:

                   CONTRACT DEPLOYED
                           │
                           ▼
                CREATE LP PAIR WITH WBNB
                           │
                           ▼
           ENABLE BUY/SELL LOGIC THROUGH ROUTER



===============================================================================
LIMIT SYSTEM (ANTI-WHALE)

Initial values:
- maxTxAmount = 2% of supply
- maxWalletAmount = 2% of supply

Limits apply to:
- buys, sells, wallet transfers (unless excluded)

After trading opens:
- Limits can only be INCREASED, never lowered.

                     ANY TRANSACTION
                           │
                           ▼
                    LIMIT CHECK APPLIES?
                           │
               ┌──────────┴────────────┐
               │                       │
               ▼                       ▼
        Address excluded?       Not excluded
               │                       │
               ▼                       ▼
            No limits               Enforce:
                             maxTxAmount / maxWalletAmount



===============================================================================
COOLDOWN SYSTEM (BUY ONLY)

- 10-second cooldown on BUY transactions from liquidity.
- Prevents rapid sniping.

                       BUY FROM LP
                           │
                           ▼
                 lastBuyTimestamp checked
                           │
               ┌──────────┴────────────┐
               │                       │
               ▼                       ▼
        10s passed?              Not passed
               │                       │
               ▼                       ▼
          BUY allowed             BUY rejected



===============================================================================
TRADING ENABLE SEQUENCE

The token starts locked.

                       BEFORE TRADING
                           │
                           ▼
       Only fee-exempt addresses can transfer tokens

To start trading:
- charityWallet must be set
- owner calls enableTrading()

                 ENABLE TRADING CALLED
                           │
                           ▼
             tradingEnabled = true (forever)
                           │
                           ▼
        charityWalletLocked = true (cannot change)
                           │
                           ▼
    Fee & Limit exclusions become immutable forever



===============================================================================
FEE COLLECTION → SWAPBACK ENGINE

A 5% tax is applied ONLY on buys/sells through LP:

                  BUY/SELL THROUGH LP
                           │
                           ▼
                 TAKE 5% FEE FROM AMOUNT
                           │
                           ▼
    ┌───────────────┬───────────────────────────┬─────────────────┐
    │               │                           │                 │
    ▼               ▼                           ▼                 ▼
1% burned    1% stored as liquidity tokens   3% stored as charity tokens
(burn now)     (accumulate)                    (accumulate)


Total tokens collected by contract for SwapBack = 4% (1%+3%).



===============================================================================
SWAPBACK TRIGGER LOGIC (IMPORTANT & EXACTLY LIKE CONTRACT)

SwapBack happens ONLY when ALL following conditions are TRUE:

Condition 1 → transaction is a SELL  
Condition 2 → swapEnabled == true  
Condition 3 → tradingEnabled == true  
Condition 4 → not currently swapping  
Condition 5 → contract token balance >= swapThreshold  

swapThreshold is defined as:

    swapThreshold = (totalSupply * 5) / 10_000

Since total supply = 10,000,000:
swapThreshold = 10,000,000 * 0.0005 = 5,000 KNR  
(This equals 0.05% of the total supply.)

Only when ≥ 5,000 KNR is collected does SwapBack activate.

ASCII FLOW:

                       SELL OCCURS
                           │
                           ▼
            Is contractBalance ≥ 5000 KNR?
                           │
           ┌───────────────┴────────────────┐
           │                                │
           ▼                                ▼
        NO → do nothing             YES → continue
                                            │
                                            ▼
                              swapEnabled = true?
                                            │
                     ┌──────────────────────┴───────────────────┐
                     │                                          │
                     ▼                                          ▼
                  NO → stop                           YES → continue
                                                                │
                                                                ▼
                                         tradingEnabled = true?
                                                                │
                     ┌──────────────────────────────────────────┴─────────┐
                     │                                                    │
                     ▼                                                    ▼
                  NO → stop                                     YES → SWAPBACK RUNS



===============================================================================
SWAPBACK EXECUTION (TOKEN → BNB → LP/CHARITY)

Once SwapBack is triggered, fee tokens are split:

liquidityTokens = 1/4 of contract's fee tokens  
charityTokens   = 3/4 of contract's fee tokens  

Liquidity tokens are further split:

                         LIQUIDITY TOKENS
                               │
                     ┌────────┴─────────┐
                     │                  │
                     ▼                  ▼
               Half kept         Half swapped to BNB



FULL SWAPBACK ASCII FLOW:

              CONTRACT FEE TOKENS (4%)
                        │
            ┌───────────┼──────────────────┐
            │           │                  │
            ▼           ▼                  ▼
        1% for LP   Split into 2        3% for Charity
                        │                     │
                        ▼                     ▼
               half KNR / half BNB     swapped to BNB
                        │                     │
                        ▼                     ▼
            KNR+BNB → Add Liquidity      Send BNB to Vault
                        │
                        ▼
             LP TOKENS → DEAD ADDRESS
            (permanently locked)



===============================================================================
WALLET-TO-WALLET TRANSFER LOGIC

               WALLET → WALLET TRANSFER
                           │
                           ▼
                   IS IT LP BUY/SELL?
                           │
         ┌─────────────────┴───────────────────┐
         │                                     │
         ▼                                     ▼
        NO                                 YES
         │                                     │
         ▼                                     ▼
  No tax applies                       5% tax applies
  No burn
  No liquidity
  No charity fee



===============================================================================
CHARITY VAULT CONTRACT — EXACT BEHAVIOR

The Vault stores and forwards BNB generated by the token.

WHEN BNB ENTERS VIA:
- direct donation
- receive()
- KNR token contract sending charity BNB

ASCII FLOW:

                 BNB ARRIVES IN VAULT
                           │
                           ▼
          Is charityWallet already set?
                           │
            ┌──────────────┴──────────────────────┐
            │                                     │
            ▼                                     ▼
         NO SET                                 SET
            │                                     │
            ▼                                     ▼
     store BNB in Vault                try auto-forward to charity
     increase totalRaised              if fail → keep BNB safely
     donorTotal updated                donorTotal updated



SETTING CHARITY WALLET

                      OWNER CALLS setCharityWallet
                                   │
                                   ▼
                         charityWallet updated
                                   │
                                   ▼
              Vault tries to send ALL stored BNB to new charity
                                   │
              ┌────────────────────┴────────────────────────┐
              │                                             │
              ▼                                             ▼
        Forward succeeds                           Forward fails
              │                                             │
              ▼                                             ▼
     Balance becomes 0                             BNB stays in Vault



LOCKING CHARITY

                 OWNER CALLS lockCharity
                           │
                           ▼
         charityLocked = true (permanent & irreversible)



SWEEP FUNCTION (FAILSAFE)

If auto-forward fails earlier:

                    OWNER CALLS sweepToCharity
                                 │
                                 ▼
                 try sending Vault BNB → charityWallet



===============================================================================
FULL SYSTEM DIAGRAM (END-TO-END)


                         USER BUYS / SELLS
                                 │
                                 ▼
                          KNR TOKEN CONTRACT
                                 │
           ┌───────────────┬───────────────┬────────────────┐
           │               │               │                │
           ▼               ▼               ▼                ▼
       1% Burn       1% Liquidity     3% Charity        Transfer 95%
                       (stored)       (stored)            to user
                                 │
                                 ▼
                 CONTRACT FEE TOKENS ACCUMULATE
                                 │
                 Meets 5,000 KNR threshold?
                                 │
                                 ▼
                            SWAPBACK
                                 │
          ┌──────────────────────┴───────────────────────────┐
          │                                                  │
          ▼                                                  ▼
 Add LP (burn LP forever)                             Swap BNB for charity
                                                             │
                                                             ▼
                                                 SEND BNB → CHARITY VAULT
                                                             │
                ┌────────────────────────────────────────────┴─────────────┐
                │                                                          │
                ▼                                                          ▼
       charityWallet NOT set                                     charityWallet SET
                │                                                          │
                ▼                                                          ▼
      BNB stored safely in Vault                              BNB auto-forwarded
                                                              to real charity wallet



===============================================================================
SUMMARY OF GUARANTEES

- Fixed 5% tax (1 burn, 1 LP, 3 charity)
- SwapBack only triggers on sells AND after reaching 0.05% supply
- LP added is permanently burned (unruggable)
- Wallet-to-wallet transfers are 0% tax
- Cooldown + Anti-whale active from launch
- Trading cannot be paused after enabling
- Fee/limit exclusions become immutable after trading
- Charity wallet in token becomes locked after trading
- Vault charity address can be changed until locked
- Owner can never withdraw charity BNB personally
- All flows visible on-chain in real time


===============================================================================
END OF README
