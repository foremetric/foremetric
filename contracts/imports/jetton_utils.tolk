// jetton_utils.tolk — Shared utilities for $FORE Jetton 2.0
// TEP-74 + TEP-89 compliant helper functions
// Tolk 0.13 syntax

tolk 0.13

// ─── Op codes ────────────────────────────────────────────────────────────────
const OP_TRANSFER: int              = 0xf8a7ea5;
const OP_TRANSFER_NOTIFICATION: int = 0x7362d09c;
const OP_INTERNAL_TRANSFER: int     = 0x178d4519;
const OP_EXCESSES: int              = 0xd53276db;
const OP_BURN: int                  = 0x595f07bc;
const OP_BURN_NOTIFICATION: int     = 0x7bdd97de;
const OP_MINT: int                  = 0x1;
const OP_CHANGE_ADMIN: int          = 0x4;
const OP_CHANGE_CONTENT: int        = 0x5;

// ─── Workchain ────────────────────────────────────────────────────────────────
const WORKCHAIN: int = 0;

// ─── Gas constants ────────────────────────────────────────────────────────────
const GAS_CONSUMPTION: int     = 15000000;  // 0.015 TON
const MIN_STORAGE: int         = 10000000;  // 0.01 TON

// ─── Helper: build addr_std from workchain + hash ────────────────────────────
fun makeAddress(workchain: int, hash: int): address {
    return beginCell()
        .storeUint(4, 3)        // addr_std$10 + no anycast
        .storeInt(workchain, 8)
        .storeUint(hash, 256)
        .endCell()
        .beginParse()
        .loadAddress();
}

// ─── Helper: calculate jetton wallet state-init cell ─────────────────────────
fun calcWalletStateInit(ownerAddress: address, minterAddress: address, walletCode: cell): cell {
    var data: cell = beginCell()
        .storeCoins(0)
        .storeAddress(ownerAddress)
        .storeAddress(minterAddress)
        .storeRef(walletCode)
        .endCell();
    return beginCell()
        .storeUint(0, 2)        // split_depth=none, special=none
        .storeMaybeRef(walletCode)  // code (present + ref)
        .storeMaybeRef(data)        // data (present + ref)
        .storeUint(0, 1)            // no library
        .endCell();
}

// ─── Helper: get wallet address for owner ────────────────────────────────────
fun calcWalletAddress(ownerAddress: address, minterAddress: address, walletCode: cell): address {
    var stateInit: cell = calcWalletStateInit(ownerAddress, minterAddress, walletCode);
    return makeAddress(WORKCHAIN, stateInit.hash());
}

// ─── Helper: send a message (no state init) ───────────────────────────────────
// TL-B: 105 bits zeros + init_present=0 + body_as_ref=1
fun sendMsg(to: address, amount: int, body: cell, mode: int) {
    var msg: cell = beginCell()
        .storeUint(0x18, 6)               // flags: nobounce, addr_std
        .storeAddress(to)
        .storeCoins(amount)
        .storeUint(0, 1 + 4 + 4 + 64 + 32)  // extra_currency + fees + timestamps = 105 bits
        .storeUint(0, 1)                      // no state init
        .storeUint(1, 1)                      // body as ref
        .storeRef(body)
        .endCell();
    sendRawMessage(msg, mode);
}

// ─── Helper: send a message with state init (deploys new wallet) ──────────────
// TL-B: CommonMsgInfo → after value coins → extra_currency(1) + ihr_fee(4) + fwd_fee(4)
//   + created_lt(64) + created_at(32) = 105 bits
// Then: init_present(1)=1 + init_as_ref(1)=1 + body_as_ref(1)=1 → 0b111 = 7 in 3 bits
fun sendMsgWithStateInit(to: address, amount: int, stateInit: cell, body: cell, mode: int) {
    var msg: cell = beginCell()
        .storeUint(0x18, 6)
        .storeAddress(to)
        .storeCoins(amount)
        .storeUint(0, 1 + 4 + 4 + 64 + 32)  // extra_currency + fees + timestamps = 105 bits
        .storeUint(7, 3)                      // init_present=1, init_as_ref=1, body_as_ref=1
        .storeRef(stateInit)
        .storeRef(body)
        .endCell();
    sendRawMessage(msg, mode);
}

// ─── Helper: pack burn notification body ─────────────────────────────────────
fun packBurnNotification(queryId: int, burnAmount: int, ownerAddress: address, responseAddress: address): cell {
    return beginCell()
        .storeUint(OP_BURN_NOTIFICATION, 32)
        .storeUint(queryId, 64)
        .storeCoins(burnAmount)
        .storeAddress(ownerAddress)
        .storeAddress(responseAddress)
        .endCell();
}

// ─── Helper: pack internal transfer body ─────────────────────────────────────
fun packInternalTransfer(queryId: int, amount: int, fromAddress: address, responseAddress: address, forwardTon: int): cell {
    return beginCell()
        .storeUint(OP_INTERNAL_TRANSFER, 32)
        .storeUint(queryId, 64)
        .storeCoins(amount)
        .storeAddress(fromAddress)
        .storeAddress(responseAddress)
        .storeCoins(forwardTon)
        .storeUint(0, 1)        // no forward payload
        .endCell();
}
