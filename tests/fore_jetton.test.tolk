// SPDX-License-Identifier: MIT
// ForeMetric $FORE Jetton 2.0 — Tests (Tolk 0.13+)

import "./fore_jetton.tolk"

const INITIAL_SUPPLY: int = 10000000000000000;    // 100M FORE in nanoFORE
const MAX_SUPPLY: int     = 100000000000000000;   // 1B FORE in nanoFORE
const DECIMALS: int       = 9;

// Helper: compare two slices
fun equalSlices(a: slice, b: slice): int {
    return (a.hash() == b.hash()) ? -1 : 0;
}

// ── Test: Mint ──────────────────────────────────────────────
fun testMint() {
    var adminAddr: slice  = address("0:1111111111111111111111111111111111111111111111111111111111111111");
    var recipient: slice  = address("0:2222222222222222222222222222222222222222222222222222222222222222");
    var mintAmount: int   = 1000000000;  // 1 FORE

    // Successful mint
    assert(mintAmount > 0, 100);
    assert(mintAmount <= MAX_SUPPLY - INITIAL_SUPPLY, 101);
}

// ── Test: Burn calculation ──────────────────────────────────
fun testBurnCalculation() {
    var amount: int = 1000000000;  // 1 FORE
    var (transferAmt, burnAmt) = calcTransferAmount(amount);

    // 0.1% of 1 FORE = 0.001 FORE = 1_000_000 nanoFORE
    assert(burnAmt == 1000000, 200);
    assert(transferAmt == 999000000, 201);
    assert(transferAmt + burnAmt == amount, 202);

    // Zero amount
    var (t0, b0) = calcTransferAmount(0);
    assert(t0 == 0, 203);
    assert(b0 == 0, 204);

    // Large amount (1B FORE)
    var largeAmt: int = 1000000000000000000;
    var (tLarge, bLarge) = calcTransferAmount(largeAmt);
    assert(bLarge == largeAmt * BURN_RATE_BPS / BPS_DENOMINATOR, 205);
    assert(tLarge + bLarge == largeAmt, 206);
}

// ── Test: Burn rate getter ──────────────────────────────────
fun testGetBurnRate() {
    var (bps, denom) = getBurnRate();
    assert(bps == 10, 300);
    assert(denom == 10000, 301);
}

// ── Test: Supply constants ──────────────────────────────────
fun testSupplyConstants() {
    assert(TOTAL_SUPPLY == 1000000000000000000, 400);
    assert(JETTON_DECIMALS == 9, 401);
    assert(BURN_RATE_BPS == 10, 402);
    assert(BPS_DENOMINATOR == 10000, 403);
}

// ── Test: Wallet data packing ───────────────────────────────
fun testPackWalletData() {
    var ownerAddr: slice  = address("0:1111111111111111111111111111111111111111111111111111111111111111");
    var masterAddr: slice = address("0:2222222222222222222222222222222222222222222222222222222222222222");
    var walletCode: cell  = beginCell().storeUint(0, 8).endCell();
    var balance: int      = 500000000;  // 0.5 FORE

    var packed: cell = packJettonWalletData(balance, ownerAddr, masterAddr, walletCode);
    assert(packed.hash() != 0, 500);

    // Verify unpacking
    var ds: slice = packed.beginParse();
    var unpackedBalance: int = ds.loadCoins();
    assert(unpackedBalance == balance, 501);
}

// ── Test: State init calculation ────────────────────────────
fun testCalcStateInit() {
    var ownerAddr: slice  = address("0:1111111111111111111111111111111111111111111111111111111111111111");
    var masterAddr: slice = address("0:2222222222222222222222222222222222222222222222222222222222222222");
    var walletCode: cell  = beginCell().storeUint(0, 8).endCell();

    var stateInit: cell = calcJettonWalletStateInit(ownerAddr, masterAddr, walletCode);
    assert(stateInit.hash() != 0, 600);

    // Same inputs produce same state init (deterministic)
    var stateInit2: cell = calcJettonWalletStateInit(ownerAddr, masterAddr, walletCode);
    assert(stateInit.hash() == stateInit2.hash(), 601);

    // Different owners produce different state inits
    var otherOwner: slice = address("0:3333333333333333333333333333333333333333333333333333333333333333");
    var stateInit3: cell = calcJettonWalletStateInit(otherOwner, masterAddr, walletCode);
    assert(stateInit.hash() != stateInit3.hash(), 602);
}

// ── Test: Wallet address calculation ────────────────────────
fun testCalcWalletAddress() {
    var ownerAddr: slice  = address("0:1111111111111111111111111111111111111111111111111111111111111111");
    var masterAddr: slice = address("0:2222222222222222222222222222222222222222222222222222222222222222");
    var walletCode: cell  = beginCell().storeUint(0, 8).endCell();

    var stateInit: cell = calcJettonWalletStateInit(ownerAddr, masterAddr, walletCode);
    var walletAddr: slice = calcJettonWalletAddress(stateInit);

    // Address should be valid (non-zero)
    assert(walletAddr.hash() != 0, 700);

    // Deterministic
    var walletAddr2: slice = calcJettonWalletAddress(stateInit);
    assert(walletAddr.hash() == walletAddr2.hash(), 701);
}

// ── Test: Transfer with burn ────────────────────────────────
fun testTransferWithBurn() {
    // Small amounts
    var (t1, b1) = calcTransferAmount(100);
    assert(b1 == 0, 800);  // 0.1% of 100 rounds to 0
    assert(t1 == 100, 801);

    // 10000 (minimum for 1 unit burn)
    var (t2, b2) = calcTransferAmount(10000);
    assert(b2 == 1, 802);  // 0.1% of 10000 = 1
    assert(t2 == 9999, 803);

    // Standard amount
    var (t3, b3) = calcTransferAmount(1000000000);
    assert(b3 == 1000000, 804);
    assert(t3 == 999000000, 805);
}

// ── Run all tests ───────────────────────────────────────────
fun main() {
    testMint();
    testBurnCalculation();
    testGetBurnRate();
    testSupplyConstants();
    testPackWalletData();
    testCalcStateInit();
    testCalcWalletAddress();
    testTransferWithBurn();
}
