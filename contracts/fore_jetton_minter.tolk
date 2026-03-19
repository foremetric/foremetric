// fore_jetton_minter.tolk — $FORE Jetton 2.0 Minter/Master Contract
//
// TEP-74 + TEP-89 compliant Jetton minter for the $FORE token.
// Fixed supply: 1,000,000,000 $FORE (9 decimals = 1_000_000_000_000_000_000 nanotons).
// Mintable ONLY once at deploy; afterwards mintable = false permanently.
//
// Storage layout:
//   coins    total_supply
//   uint1    mintable        — 1 = open (pre-mint), 0 = locked (after mint)
//   address  admin_address
//   cell     content         — off-chain metadata cell (TEP-64)
//   cell     jetton_wallet_code

tolk 0.13

import "imports/jetton_utils.tolk";

// ─── Storage helpers ──────────────────────────────────────────────────────────

fun loadData(): (int, int, address, cell, cell) {
    var ds: slice = contract.getData().beginParse();
    var totalSupply: int    = ds.loadCoins();
    var mintable: int       = ds.loadUint(1);
    var adminAddress: address = ds.loadAddress();
    var content: cell       = ds.loadRef();
    var walletCode: cell    = ds.loadRef();
    return (totalSupply, mintable, adminAddress, content, walletCode);
}

fun saveData(totalSupply: int, mintable: int, adminAddress: address, content: cell, walletCode: cell) {
    contract.setData(beginCell()
        .storeCoins(totalSupply)
        .storeUint(mintable, 1)
        .storeAddress(adminAddress)
        .storeRef(content)
        .storeRef(walletCode)
        .endCell());
}

// ─── Internal message handler ─────────────────────────────────────────────────

fun onInternalMessage(myBalance: int, msgValue: int, inMsgFull: cell, inMsgBody: slice) {
    if (inMsgBody.isEnd()) { return; }  // accept plain TON transfers

    var cs: slice = inMsgFull.beginParse();
    var flags: int = cs.loadUint(4);
    if (flags & 1) { return; }         // ignore bounced messages

    var senderAddress: address = cs.loadAddress();

    var op: int     = inMsgBody.loadUint(32);
    var queryId: int = inMsgBody.loadUint(64);

    var (totalSupply, mintable, adminAddress, content, walletCode) = loadData();

    // ── OP_MINT (0x1) — admin only, one-shot ───────────────────────────────
    if (op == OP_MINT) {
        assert(senderAddress == adminAddress, 73);  // not admin
        assert(mintable == 1, 74);                  // already minted — supply locked

        var toAddress: address = inMsgBody.loadAddress();
        var amount: int        = inMsgBody.loadCoins();
        var forwardTon: int    = inMsgBody.loadCoins();

        // Build wallet state-init and deploy with credited tokens
        var stateInit: cell   = calcWalletStateInit(toAddress, contract.getAddress(), walletCode);
        var walletAddress: address = makeAddress(WORKCHAIN, stateInit.hash());

        var mintBody: cell = beginCell()
            .storeUint(OP_INTERNAL_TRANSFER, 32)
            .storeUint(queryId, 64)
            .storeCoins(amount)
            .storeAddress(contract.getAddress())  // from = minter
            .storeAddress(adminAddress)            // excess → admin
            .storeCoins(forwardTon)
            .storeUint(0, 1)                       // no forward payload
            .endCell();

        sendMsgWithStateInit(walletAddress, msgValue - GAS_CONSUMPTION, stateInit, mintBody, 1);

        // Lock supply permanently after first mint
        saveData(totalSupply + amount, 0, adminAddress, content, walletCode);
        return;
    }

    // ── OP_BURN_NOTIFICATION (0x7bdd97de) — from wallet, reduce supply ─────
    if (op == OP_BURN_NOTIFICATION) {
        var burnAmount: int        = inMsgBody.loadCoins();
        var fromAddress: address   = inMsgBody.loadAddress();
        var responseAddress: address = inMsgBody.loadAddress();

        // Verify sender is a legitimate wallet for fromAddress
        var expectedWallet: address = calcWalletAddress(fromAddress, contract.getAddress(), walletCode);
        assert(senderAddress == expectedWallet, 74);

        // Reduce total supply
        assert(totalSupply >= burnAmount, 75);
        saveData(totalSupply - burnAmount, mintable, adminAddress, content, walletCode);

        // Return excess TON to response address
        if (!responseAddress.isNone()) {
            var excessBody: cell = beginCell()
                .storeUint(OP_EXCESSES, 32)
                .storeUint(queryId, 64)
                .endCell();
            sendMsg(responseAddress, 0, excessBody, 64);
        }
        return;
    }

    // ── OP_CHANGE_ADMIN (0x4) ──────────────────────────────────────────────
    if (op == OP_CHANGE_ADMIN) {
        assert(senderAddress == adminAddress, 73);
        var newAdmin: address = inMsgBody.loadAddress();
        saveData(totalSupply, mintable, newAdmin, content, walletCode);
        return;
    }

    // ── OP_CHANGE_CONTENT (0x5) ────────────────────────────────────────────
    if (op == OP_CHANGE_CONTENT) {
        assert(senderAddress == adminAddress, 73);
        var newContent: cell = inMsgBody.loadRef();
        saveData(totalSupply, mintable, adminAddress, newContent, walletCode);
        return;
    }

    throw 0xffff;  // unknown op
}

// ─── Get methods (TEP-74 + TEP-89) ───────────────────────────────────────────

get fun getJettonData(): (int, int, address, cell, cell) {
    var (totalSupply, mintable, adminAddress, content, walletCode) = loadData();
    return (totalSupply, mintable, adminAddress, content, walletCode);
}

get fun getWalletAddress(ownerAddress: address): address {
    var (totalSupply, mintable, adminAddress, content, walletCode) = loadData();
    return calcWalletAddress(ownerAddress, contract.getAddress(), walletCode);
}
