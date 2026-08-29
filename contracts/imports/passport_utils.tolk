// passport_utils.tolk — Shared constants and utilities for Signal Passport TEE Nullifier
// Tolk 0.13 syntax

tolk 0.13

// ─── Op Codes ─────────────────────────────────────────────────────────────────
const OP_CONSUME_QUERY: int         = 0x53500001;  // TEE query consumption & decrement
const OP_REVOKE: int                = 0x53500002;  // Instant owner revocation
const OP_UPDATE_SECTORS: int        = 0x53500003;  // Owner update of sector permissions
const OP_REGISTER_PASSPORT: int     = 0x53500004;  // Registry registration
const OP_EXCESSES: int              = 0xd53276db;  // Return excess gas

// ─── Status Codes ─────────────────────────────────────────────────────────────
const STATUS_ACTIVE: int            = 0;  // Passport active and consumable
const STATUS_REVOKED: int           = 1;  // Revoked by owner (burned permanently)
const STATUS_BURNED_LIMIT: int      = 2;  // Burned permanently (query limit reached)
const STATUS_EXPIRED: int           = 3;  // Expired by timestamp

// ─── Error Exit Codes ─────────────────────────────────────────────────────────
const ERR_UNAUTHORIZED: int         = 801;  // Sender not authorized
const ERR_NOT_ACTIVE: int           = 802;  // Passport not in active state
const ERR_LIMIT_REACHED: int        = 803;  // No remaining queries
const ERR_EXPIRED: int              = 804;  // Passport has expired
const ERR_SECTOR_NOT_ALLOWED: int   = 805;  // Requested sector not permitted
const ERR_INVALID_LIMIT: int        = 806;  // Query limit out of range (1..9999)

// ─── Constants ────────────────────────────────────────────────────────────────
const WORKCHAIN: int                = 0;
const MAX_QUERY_LIMIT: int          = 9999;
const MIN_QUERY_LIMIT: int          = 1;

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

// ─── Helper: send standard message ───────────────────────────────────────────
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

// ─── Helper: send simple excess return ────────────────────────────────────────
fun sendExcesses(to: address, queryId: int, mode: int) {
    if (to.isNone()) { return; }
    var excessBody: cell = beginCell()
        .storeUint(OP_EXCESSES, 32)
        .storeUint(queryId, 64)
        .endCell();
    sendMsg(to, 0, excessBody, mode);
}
