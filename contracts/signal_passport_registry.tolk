// signal_passport_registry.tolk — Signal Passport Registry & Factory Contract
//
// Manages registration of Signal Passport cryptographic nullifiers on TON blockchain.
// Computes deterministic passport contract addresses via StateInit, deploys passport
// instances upon token generation, and coordinates authorized Cocoon TEE verifiers.
//
// Tolk 0.13 syntax

tolk 0.13

import "imports/passport_utils.tolk";

// ─── Storage layout ───────────────────────────────────────────────────────────
//   address  admin_address
//   address  tee_verifier_address
//   cell     passport_code
//   uint64   total_passports_registered

fun loadData(): (address, address, cell, int) {
    var ds: slice = contract.getData().beginParse();
    var adminAddress: address        = ds.loadAddress();
    var teeVerifierAddress: address  = ds.loadAddress();
    var passportCode: cell           = ds.loadRef();
    var totalRegistered: int         = ds.loadUint(64);
    return (adminAddress, teeVerifierAddress, passportCode, totalRegistered);
}

fun saveData(adminAddress: address, teeVerifierAddress: address, passportCode: cell, totalRegistered: int) {
    contract.setData(beginCell()
        .storeAddress(adminAddress)
        .storeAddress(teeVerifierAddress)
        .storeRef(passportCode)
        .storeUint(totalRegistered, 64)
        .endCell());
}

// ─── Passport StateInit calculation ──────────────────────────────────────────

fun calcPassportStateInit(
    ownerAddress: address,
    teeVerifierAddress: address,
    nullifierHash: int,
    tokenIdCell: cell,
    queryLimit: int,
    sectorsMask: int,
    expiryTimestamp: int,
    passportCode: cell
): cell {
    var data: cell = beginCell()
        .storeAddress(ownerAddress)
        .storeAddress(teeVerifierAddress)
        .storeUint(nullifierHash, 256)
        .storeRef(tokenIdCell)
        .storeUint(queryLimit, 16)
        .storeUint(queryLimit, 16)  // remaining_queries = query_limit initially
        .storeUint(sectorsMask, 32)
        .storeUint(expiryTimestamp, 64)
        .storeUint(STATUS_ACTIVE, 8) // status = ACTIVE (0)
        .endCell();

    return beginCell()
        .storeUint(0, 2)        // split_depth=none, special=none
        .storeUint(1, 1)        // code present
        .storeRef(passportCode) // code cell ref
        .storeUint(1, 1)        // data present
        .storeRef(data)         // data cell ref
        .storeUint(0, 1)        // no library
        .endCell();
}

fun calcPassportAddress(
    ownerAddress: address,
    teeVerifierAddress: address,
    nullifierHash: int,
    tokenIdCell: cell,
    queryLimit: int,
    sectorsMask: int,
    expiryTimestamp: int,
    passportCode: cell
): address {
    var stateInit: cell = calcPassportStateInit(
        ownerAddress,
        teeVerifierAddress,
        nullifierHash,
        tokenIdCell,
        queryLimit,
        sectorsMask,
        expiryTimestamp,
        passportCode
    );
    return makeAddress(WORKCHAIN, stateInit.hash());
}

// ─── Internal message handler ─────────────────────────────────────────────────

fun onInternalMessage(myBalance: int, msgValue: int, inMsgFull: cell, inMsgBody: slice) {
    if (inMsgBody.isEnd()) { return; }

    var cs: slice = inMsgFull.beginParse();
    var flags: int = cs.loadUint(4);
    if (flags & 1) { return; }

    var senderAddress: address = cs.loadAddress();
    var op: int      = inMsgBody.loadUint(32);
    var queryId: int = inMsgBody.loadUint(64);

    var (adminAddress, teeVerifierAddress, passportCode, totalRegistered) = loadData();

    // ── OP_REGISTER_PASSPORT (0x53500004) — Register and deploy Signal Passport ──
    if (op == OP_REGISTER_PASSPORT) {
        var ownerAddress: address    = inMsgBody.loadAddress();
        var nullifierHash: int       = inMsgBody.loadUint(256);
        var tokenIdCell: cell        = inMsgBody.loadRef();
        var queryLimit: int          = inMsgBody.loadUint(16);
        var sectorsMask: int         = inMsgBody.loadUint(32);
        var expiryTimestamp: int     = inMsgBody.loadUint(64);
        var responseAddress: address = inMsgBody.loadAddress();

        // Validate query limit (1 to 9,999 per spec)
        assert(queryLimit >= MIN_QUERY_LIMIT, ERR_INVALID_LIMIT);
        assert(queryLimit <= MAX_QUERY_LIMIT, ERR_INVALID_LIMIT);

        // Build passport state-init and deterministic address
        var stateInit: cell = calcPassportStateInit(
            ownerAddress,
            teeVerifierAddress,
            nullifierHash,
            tokenIdCell,
            queryLimit,
            sectorsMask,
            expiryTimestamp,
            passportCode
        );
        var passportAddress: address = makeAddress(WORKCHAIN, stateInit.hash());

        // Empty deploy body accepted by onInternalMessage
        var deployBody: cell = beginCell().endCell();

        // Send deploy message with remaining gas
        var msg: cell = beginCell()
            .storeUint(0x18, 6)
            .storeAddress(passportAddress)
            .storeCoins(0)
            .storeUint(0, 1 + 4 + 4 + 64 + 32)
            .storeUint(7, 3)  // init=1, init_as_ref=1, body_as_ref=1
            .storeRef(stateInit)
            .storeRef(deployBody)
            .endCell();
        sendRawMessage(msg, 64);  // carry remaining gas

        totalRegistered += 1;
        saveData(adminAddress, teeVerifierAddress, passportCode, totalRegistered);
        return;
    }

    // ── Admin: Set TEE verifier address ───────────────────────────────────────
    if (op == 0x10) {
        assert(senderAddress == adminAddress, ERR_UNAUTHORIZED);
        var newTeeVerifier: address = inMsgBody.loadAddress();
        saveData(adminAddress, newTeeVerifier, passportCode, totalRegistered);
        sendExcesses(senderAddress, queryId, 64);
        return;
    }

    // ── Admin: Change admin ───────────────────────────────────────────────────
    if (op == 0x11) {
        assert(senderAddress == adminAddress, ERR_UNAUTHORIZED);
        var newAdmin: address = inMsgBody.loadAddress();
        saveData(newAdmin, teeVerifierAddress, passportCode, totalRegistered);
        sendExcesses(senderAddress, queryId, 64);
        return;
    }

    throw 0xffff;
}

// ─── Get Methods ──────────────────────────────────────────────────────────────

get fun getRegistryData(): (address, address, cell, int) {
    var (adminAddress, teeVerifierAddress, passportCode, totalRegistered) = loadData();
    return (adminAddress, teeVerifierAddress, passportCode, totalRegistered);
}

get fun getPassportAddress(
    ownerAddress: address,
    nullifierHash: int,
    tokenIdCell: cell,
    queryLimit: int,
    sectorsMask: int,
    expiryTimestamp: int
): address {
    var (adminAddress, teeVerifierAddress, passportCode, totalRegistered) = loadData();
    return calcPassportAddress(
        ownerAddress,
        teeVerifierAddress,
        nullifierHash,
        tokenIdCell,
        queryLimit,
        sectorsMask,
        expiryTimestamp,
        passportCode
    );
}
