// signal_passport.tolk — Signal Passport TEE Nullifier Smart Contract
//
// Cryptographic nullifier mechanism for Signal Passport on TON blockchain.
// Ensures a passport token can only be consumed up to `query_limit` times,
// decrements on-chain on each verified Cocoon TEE response, burns permanently
// upon limit exhaustion (zero replay attacks), and supports instant owner revocation.
//
// Tolk 0.13 syntax

tolk 0.13

import "imports/passport_utils.tolk";

// ─── Storage layout ───────────────────────────────────────────────────────────
//   address  owner_address
//   address  tee_verifier_address
//   uint256  nullifier_hash
//   cell     token_id_cell       — stores string slice (e.g. "SP-4821-2026")
//   uint16   query_limit         — 1 to 9,999
//   uint16   remaining_queries   — decrements on each query consumption
//   uint32   sectors_mask        — bitmask for open/closed behavioral sectors
//   uint64   expiry_timestamp    — unix timestamp, 0 = unlimited
//   uint8    status              — 0: ACTIVE, 1: REVOKED, 2: BURNED_LIMIT, 3: EXPIRED

fun loadData(): (address, address, int, cell, int, int, int, int, int) {
    var ds: slice = contract.getData().beginParse();
    var ownerAddress: address        = ds.loadAddress();
    var teeVerifierAddress: address  = ds.loadAddress();
    var nullifierHash: int           = ds.loadUint(256);
    var tokenIdCell: cell            = ds.loadRef();
    var queryLimit: int              = ds.loadUint(16);
    var remainingQueries: int        = ds.loadUint(16);
    var sectorsMask: int             = ds.loadUint(32);
    var expiryTimestamp: int         = ds.loadUint(64);
    var status: int                  = ds.loadUint(8);
    return (ownerAddress, teeVerifierAddress, nullifierHash, tokenIdCell, queryLimit, remainingQueries, sectorsMask, expiryTimestamp, status);
}

fun saveData(
    ownerAddress: address,
    teeVerifierAddress: address,
    nullifierHash: int,
    tokenIdCell: cell,
    queryLimit: int,
    remainingQueries: int,
    sectorsMask: int,
    expiryTimestamp: int,
    status: int
) {
    contract.setData(beginCell()
        .storeAddress(ownerAddress)
        .storeAddress(teeVerifierAddress)
        .storeUint(nullifierHash, 256)
        .storeRef(tokenIdCell)
        .storeUint(queryLimit, 16)
        .storeUint(remainingQueries, 16)
        .storeUint(sectorsMask, 32)
        .storeUint(expiryTimestamp, 64)
        .storeUint(status, 8)
        .endCell());
}

// ─── Internal message handler ─────────────────────────────────────────────────

fun onInternalMessage(myBalance: int, msgValue: int, inMsgFull: cell, inMsgBody: slice) {
    if (inMsgBody.isEnd()) { return; }  // accept plain TON transfers and empty deploy bodies

    var cs: slice = inMsgFull.beginParse();
    var flags: int = cs.loadUint(4);
    if (flags & 1) { return; }         // ignore bounced messages

    var senderAddress: address = cs.loadAddress();
    var op: int      = inMsgBody.loadUint(32);
    var queryId: int = inMsgBody.loadUint(64);

    // Accept excesses or notifications
    if (op == OP_EXCESSES) { return; }

    var (
        ownerAddress,
        teeVerifierAddress,
        nullifierHash,
        tokenIdCell,
        queryLimit,
        remainingQueries,
        sectorsMask,
        expiryTimestamp,
        status
    ) = loadData();

    // ── OP_CONSUME_QUERY (0x53500001) — Cocoon TEE verified query consumption ─
    if (op == OP_CONSUME_QUERY) {
        // 1. Verify caller is authorized Cocoon TEE verifier
        assert(senderAddress == teeVerifierAddress, ERR_UNAUTHORIZED);

        // 2. Verify passport is currently active
        assert(status == STATUS_ACTIVE, ERR_NOT_ACTIVE);

        // 3. Verify expiry
        if (expiryTimestamp > 0) {
            assert(blockchain.now() <= expiryTimestamp, ERR_EXPIRED);
        }

        // 4. Verify remaining queries > 0
        assert(remainingQueries > 0, ERR_LIMIT_REACHED);

        // 5. Verify requested sectors are within authorized sector mask
        var requestedSectors: int = inMsgBody.loadUint(32);
        var responseAddress: address = inMsgBody.loadAddress();

        assert((requestedSectors & sectorsMask) == requestedSectors, ERR_SECTOR_NOT_ALLOWED);

        // 6. Decrement counter on-chain
        remainingQueries -= 1;

        // 7. If counter reaches 0, burn permanently (zero replay attacks possible)
        if (remainingQueries == 0) {
            status = STATUS_BURNED_LIMIT;
        }

        saveData(
            ownerAddress,
            teeVerifierAddress,
            nullifierHash,
            tokenIdCell,
            queryLimit,
            remainingQueries,
            sectorsMask,
            expiryTimestamp,
            status
        );

        // Return excess gas & confirmation notification
        sendExcesses(responseAddress, queryId, 64);
        return;
    }

    // ── OP_REVOKE (0x53500002) — Instant owner revocation at any time ─────────
    if (op == OP_REVOKE) {
        // Only passport owner can revoke
        assert(senderAddress == ownerAddress, ERR_UNAUTHORIZED);

        var responseAddress: address = inMsgBody.loadAddress();

        // Mark as revoked and zero remaining queries (burns permanently)
        status = STATUS_REVOKED;
        remainingQueries = 0;

        saveData(
            ownerAddress,
            teeVerifierAddress,
            nullifierHash,
            tokenIdCell,
            queryLimit,
            remainingQueries,
            sectorsMask,
            expiryTimestamp,
            status
        );

        sendExcesses(responseAddress, queryId, 64);
        return;
    }

    // ── OP_UPDATE_SECTORS (0x53500003) — Owner sector configuration update ────
    if (op == OP_UPDATE_SECTORS) {
        assert(senderAddress == ownerAddress, ERR_UNAUTHORIZED);
        assert(status == STATUS_ACTIVE, ERR_NOT_ACTIVE);

        var newSectorsMask: int = inMsgBody.loadUint(32);
        var responseAddress: address = inMsgBody.loadAddress();

        sectorsMask = newSectorsMask;

        saveData(
            ownerAddress,
            teeVerifierAddress,
            nullifierHash,
            tokenIdCell,
            queryLimit,
            remainingQueries,
            sectorsMask,
            expiryTimestamp,
            status
        );

        sendExcesses(responseAddress, queryId, 64);
        return;
    }

    throw 0xffff;  // unknown op
}

// ─── Get Methods ──────────────────────────────────────────────────────────────

get fun getPassportData(): (address, address, int, cell, int, int, int, int, int) {
    var (
        ownerAddress,
        teeVerifierAddress,
        nullifierHash,
        tokenIdCell,
        queryLimit,
        remainingQueries,
        sectorsMask,
        expiryTimestamp,
        status
    ) = loadData();
    return (
        ownerAddress,
        teeVerifierAddress,
        nullifierHash,
        tokenIdCell,
        queryLimit,
        remainingQueries,
        sectorsMask,
        expiryTimestamp,
        status
    );
}

get fun getNullifierHash(): int {
    var (
        ownerAddress,
        teeVerifierAddress,
        nullifierHash,
        tokenIdCell,
        queryLimit,
        remainingQueries,
        sectorsMask,
        expiryTimestamp,
        status
    ) = loadData();
    return nullifierHash;
}

get fun getRemainingQueries(): int {
    var (
        ownerAddress,
        teeVerifierAddress,
        nullifierHash,
        tokenIdCell,
        queryLimit,
        remainingQueries,
        sectorsMask,
        expiryTimestamp,
        status
    ) = loadData();
    return remainingQueries;
}

get fun getStatus(): int {
    var (
        ownerAddress,
        teeVerifierAddress,
        nullifierHash,
        tokenIdCell,
        queryLimit,
        remainingQueries,
        sectorsMask,
        expiryTimestamp,
        status
    ) = loadData();

    if (status == STATUS_ACTIVE && expiryTimestamp > 0 && blockchain.now() > expiryTimestamp) {
        return STATUS_EXPIRED;
    }
    return status;
}

get fun isValidForQuery(requestedSectors: int): (int, int, int) {
    var (
        ownerAddress,
        teeVerifierAddress,
        nullifierHash,
        tokenIdCell,
        queryLimit,
        remainingQueries,
        sectorsMask,
        expiryTimestamp,
        status
    ) = loadData();

    if (status != STATUS_ACTIVE) {
        return (0, remainingQueries, status);
    }
    if (expiryTimestamp > 0 && blockchain.now() > expiryTimestamp) {
        return (0, remainingQueries, STATUS_EXPIRED);
    }
    if (remainingQueries <= 0) {
        return (0, 0, STATUS_BURNED_LIMIT);
    }
    if ((requestedSectors & sectorsMask) != requestedSectors) {
        return (0, remainingQueries, status);
    }

    return (1, remainingQueries, STATUS_ACTIVE);
}
