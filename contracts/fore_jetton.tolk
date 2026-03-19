// SPDX-License-Identifier: MIT
// ForeMetric $FORE Jetton 2.0 — Tolk 0.13+
// Fixed supply: 1,000,000,000 FORE (1B)
// Burn rate: 0.1% on transfers
// Implements Jetton 2.0 standard on TON

import "@stdlib/tvm-lowlevel"

const JETTON_DECIMALS: int = 9;
const TOTAL_SUPPLY: int = 1000000000000000000;   // 1B * 10^9
const BURN_RATE_BPS: int = 10;                    // 0.1% = 10 basis points
const BPS_DENOMINATOR: int = 10000;

// ── Op-codes (Jetton 2.0 standard) ─────────────────────────
const OP_TRANSFER: int          = 0xf8a7ea5;
const OP_TRANSFER_NOTIFICATION: int = 0x7362d09c;
const OP_INTERNAL_TRANSFER: int = 0x178d4519;
const OP_EXCESSES: int          = 0xd53276db;
const OP_BURN: int              = 0x595f07bc;
const OP_BURN_NOTIFICATION: int = 0x7bdd97de;
const OP_MINT: int              = 0x15;
const OP_CHANGE_ADMIN: int      = 0x3;
const OP_PROVIDE_WALLET: int    = 0x2c76b973;
const OP_TAKE_WALLET: int       = 0xd1735400;

// ── Storage ─────────────────────────────────────────────────
// total_supply:Coins  admin_address:MsgAddress  content:^Cell  jetton_wallet_code:^Cell

fun saveData(totalSupply: int, adminAddr: slice, content: cell, walletCode: cell) {
    setData(
        beginCell()
            .storeCoins(totalSupply)
            .storeSlice(adminAddr)
            .storeRef(content)
            .storeRef(walletCode)
        .endCell()
    );
}

fun loadData(): (int, slice, cell, cell) {
    var ds: slice = getData().beginParse();
    return (
        ds.loadCoins(),
        ds.loadAddress(),
        ds.loadRef(),
        ds.loadRef()
    );
}

fun packJettonWalletData(
    balance: int,
    ownerAddr: slice,
    masterAddr: slice,
    walletCode: cell
): cell {
    return beginCell()
        .storeCoins(balance)
        .storeSlice(ownerAddr)
        .storeSlice(masterAddr)
        .storeRef(walletCode)
    .endCell();
}

fun calcJettonWalletStateInit(
    ownerAddr: slice,
    masterAddr: slice,
    walletCode: cell
): cell {
    return beginCell()
        .storeUint(0, 2)
        .storeDict(walletCode)
        .storeDict(
            packJettonWalletData(0, ownerAddr, masterAddr, walletCode)
        )
        .storeUint(0, 1)
    .endCell();
}

fun calcJettonWalletAddress(stateInit: cell): slice {
    return beginCell()
        .storeUint(4, 3)
        .storeInt(0, 8)
        .storeUint(stateInit.hash(), 256)
    .endCell().beginParse();
}

// ── Burn calculation ────────────────────────────────────────
fun calcBurnAmount(amount: int): int {
    return (amount * BURN_RATE_BPS) / BPS_DENOMINATOR;
}

fun calcTransferAmount(amount: int): (int, int) {
    var burnAmt: int = calcBurnAmount(amount);
    return (amount - burnAmt, burnAmt);
}

// ── Message handling ────────────────────────────────────────
fun onInternalMessage(myBalance: int, msgValue: int, inMsgFull: cell, inMsgBody: slice) {
    if (inMsgBody.isEndOfSlice()) {
        return;
    }

    var cs: slice = inMsgFull.beginParse();
    var flags: int = cs.loadUint(4);
    if (flags & 1) {  // bounced
        inMsgBody.skipBits(32);
        var op: int = inMsgBody.loadUint(32);
        if ((op == OP_INTERNAL_TRANSFER) | (op == OP_BURN_NOTIFICATION)) {
            var jettonAmount: int = inMsgBody.loadCoins();
            var (totalSupply, adminAddr, content, walletCode) = loadData();
            saveData(totalSupply + jettonAmount, adminAddr, content, walletCode);
        }
        return;
    }

    var senderAddr: slice = cs.loadAddress();
    var op: int = inMsgBody.loadUint(32);
    var queryId: int = inMsgBody.loadUint(64);

    var (totalSupply, adminAddr, content, walletCode) = loadData();

    if (op == OP_MINT) {
        assert(senderAddr.hash() == adminAddr.hash(), 73);
        var toAddr: slice = inMsgBody.loadAddress();
        var amount: int = inMsgBody.loadCoins();
        var masterMsg: cell = inMsgBody.loadRef();

        var stateInit: cell = calcJettonWalletStateInit(toAddr, myAddress(), walletCode);
        var toWalletAddr: slice = calcJettonWalletAddress(stateInit);

        sendRawMessage(
            beginCell()
                .storeUint(0x18, 6)
                .storeSlice(toWalletAddr)
                .storeCoins(amount)
                .storeUint(4 + 2 + 1, 1 + 4 + 4 + 64 + 32 + 1 + 1 + 1)
                .storeRef(stateInit)
                .storeRef(masterMsg)
            .endCell(),
            1
        );
        saveData(totalSupply + amount, adminAddr, content, walletCode);
        return;
    }

    if (op == OP_BURN_NOTIFICATION) {
        var jettonAmount: int = inMsgBody.loadCoins();
        var fromAddr: slice = inMsgBody.loadAddress();

        var stateInit: cell = calcJettonWalletStateInit(fromAddr, myAddress(), walletCode);
        var walletAddr: slice = calcJettonWalletAddress(stateInit);
        assert(senderAddr.hash() == walletAddr.hash(), 74);

        saveData(totalSupply - jettonAmount, adminAddr, content, walletCode);

        var responseAddr: slice = inMsgBody.loadAddress();
        if (responseAddr.preloadUint(2) != 0) {
            sendRawMessage(
                beginCell()
                    .storeUint(0x10, 6)
                    .storeSlice(responseAddr)
                    .storeCoins(0)
                    .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
                    .storeUint(OP_EXCESSES, 32)
                    .storeUint(queryId, 64)
                .endCell(),
                2
            );
        }
        return;
    }

    if (op == OP_PROVIDE_WALLET) {
        var ownerAddr: slice = inMsgBody.loadAddress();
        var includeAddr: int = inMsgBody.loadUint(1);

        var stateInit: cell = calcJettonWalletStateInit(ownerAddr, myAddress(), walletCode);
        var walletAddr: slice = calcJettonWalletAddress(stateInit);

        var body: builder = beginCell()
            .storeUint(OP_TAKE_WALLET, 32)
            .storeUint(queryId, 64);

        if (includeAddr) {
            body = body.storeSlice(walletAddr);
        }

        sendRawMessage(
            beginCell()
                .storeUint(0x18, 6)
                .storeSlice(senderAddr)
                .storeCoins(0)
                .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
                .storeBuilder(body)
            .endCell(),
            64
        );
        return;
    }

    if (op == OP_CHANGE_ADMIN) {
        assert(senderAddr.hash() == adminAddr.hash(), 73);
        var newAdmin: slice = inMsgBody.loadAddress();
        saveData(totalSupply, newAdmin, content, walletCode);
        return;
    }

    assert(false, 0xffff);
}

// ── Getters ─────────────────────────────────────────────────
get fun getJettonData(): (int, int, slice, cell, cell) {
    var (totalSupply, adminAddr, content, walletCode) = loadData();
    return (-1, totalSupply, adminAddr, content, walletCode);
}

get fun getWalletAddress(ownerAddr: slice): slice {
    var (totalSupply, adminAddr, content, walletCode) = loadData();
    return calcJettonWalletAddress(
        calcJettonWalletStateInit(ownerAddr, myAddress(), walletCode)
    );
}

get fun getBurnRate(): (int, int) {
    return (BURN_RATE_BPS, BPS_DENOMINATOR);
}

get fun calcTransferAmounts(amount: int): (int, int) {
    return calcTransferAmount(amount);
}
