// fore_jetton_wallet.tolk — $FORE Jetton 2.0 Wallet Contract
//
// TEP-74 compliant Jetton wallet for $FORE token.
// Burns 0.1% (1/1000) of every user-to-user transfer (minimum 1 nanoton).
// Burns are notified to the minter to reduce total_supply on-chain.
//
// Storage layout:
//   coins    balance
//   address  owner_address
//   address  minter_address
//   cell     jetton_wallet_code

tolk 0.13

import "imports/jetton_utils.tolk";

// ─── Storage helpers ──────────────────────────────────────────────────────────

fun loadData(): (int, address, address, cell) {
    var ds: slice = contract.getData().beginParse();
    var balance: int          = ds.loadCoins();
    var ownerAddress: address  = ds.loadAddress();
    var minterAddress: address = ds.loadAddress();
    var walletCode: cell       = ds.loadRef();
    return (balance, ownerAddress, minterAddress, walletCode);
}

fun saveData(balance: int, ownerAddress: address, minterAddress: address, walletCode: cell) {
    contract.setData(beginCell()
        .storeCoins(balance)
        .storeAddress(ownerAddress)
        .storeAddress(minterAddress)
        .storeRef(walletCode)
        .endCell());
}

// ─── Burn math ────────────────────────────────────────────────────────────────
// 0.1% burn = amount / 1000, minimum 1 nanoton
fun calcBurnAmount(amount: int): int {
    var raw: int = amount / 1000;
    if (raw < 1) {
        return 1;
    }
    return raw;
}

// ─── Internal message handler ─────────────────────────────────────────────────

fun onInternalMessage(myBalance: int, msgValue: int, inMsgFull: cell, inMsgBody: slice) {
    if (inMsgBody.isEnd()) { return; }

    var cs: slice = inMsgFull.beginParse();
    var flags: int = cs.loadUint(4);

    // Handle bounced messages: restore balance
    if (flags & 1) {
        inMsgBody.loadUint(32);   // skip 0xffffffff bounce prefix
        var opBounced: int = inMsgBody.loadUint(32);
        if (opBounced == OP_INTERNAL_TRANSFER) {
            inMsgBody.loadUint(64);   // query_id
            var bouncedAmount: int = inMsgBody.loadCoins();
            var (balance, ownerAddress, minterAddress, walletCode) = loadData();
            saveData(balance + bouncedAmount, ownerAddress, minterAddress, walletCode);
        }
        return;
    }

    var senderAddress: address = cs.loadAddress();
    var op: int       = inMsgBody.loadUint(32);
    var queryId: int  = inMsgBody.loadUint(64);

    var (balance, ownerAddress, minterAddress, walletCode) = loadData();

    // ── OP_TRANSFER (0xf8a7ea5) — send tokens P2P with 0.1% burn ────────────
    if (op == OP_TRANSFER) {
        assert(senderAddress == ownerAddress, 705);  // only owner can transfer

        var amount: int             = inMsgBody.loadCoins();
        var destination: address    = inMsgBody.loadAddress();
        var responseAddress: address = inMsgBody.loadAddress();
        inMsgBody.loadUint(1);                       // maybe custom_payload (skip flag)
        var forwardTon: int         = inMsgBody.loadCoins();

        assert(amount > 0, 706);
        assert(balance >= amount, 707);

        // Calculate 0.1% burn: max(1, amount / 1000)
        var burnAmount: int     = calcBurnAmount(amount);
        var transferAmount: int = amount - burnAmount;

        balance -= amount;
        saveData(balance, ownerAddress, minterAddress, walletCode);

        // Deploy destination wallet and credit transferAmount.
        // Include state init to auto-deploy the destination wallet if it doesn't exist.
        var destStateInit: cell  = calcWalletStateInit(destination, minterAddress, walletCode);
        var destWallet: address  = makeAddress(WORKCHAIN, destStateInit.hash());

        var transferBody: cell = packInternalTransfer(queryId, transferAmount, ownerAddress, responseAddress, forwardTon);

        // Build dest wallet message with embedded state init.
        // Use mode 64 to carry all remaining incoming TON to the dest wallet.
        // The dest wallet will handle forwarding notifications and excess.
        var destMsg: cell = beginCell()
            .storeUint(0x10, 6)                    // 0x10 = non-bounceable (deploy msg)
            .storeAddress(destWallet)
            .storeCoins(0)
            .storeUint(0, 1 + 4 + 4 + 64 + 32)
            .storeUint(7, 3)                        // init=1, init_as_ref=1, body_as_ref=1
            .storeRef(destStateInit)
            .storeRef(transferBody)
            .endCell();
        sendRawMessage(destMsg, 64);  // mode 64 = carry remaining incoming value

        // Notify minter to reduce total_supply by burnAmount.
        // Use mode 2 (ignore errors): if wallet has no stored TON for fees,
        // the burn notification won't be sent but the transfer still succeeds.
        // On mainnet, wallets accumulate storage refunds that cover this cost.
        var burnNotif: cell = packBurnNotification(queryId, burnAmount, ownerAddress, responseAddress);
        sendMsg(minterAddress, 0, burnNotif, 2);
        return;
    }

    // ── OP_INTERNAL_TRANSFER (0x178d4519) — receive tokens ───────────────────
    if (op == OP_INTERNAL_TRANSFER) {
        var amount: int              = inMsgBody.loadCoins();
        var fromAddress: address     = inMsgBody.loadAddress();
        var responseAddress: address = inMsgBody.loadAddress();
        var forwardTon: int          = inMsgBody.loadCoins();
        var hasPayload: int          = inMsgBody.loadUint(1);

        // Sender must be minter (initial mint) or a valid wallet for fromAddress
        var isFromMinter: bool = (senderAddress == minterAddress);
        if (!isFromMinter) {
            var expectedSender: address = calcWalletAddress(fromAddress, minterAddress, walletCode);
            assert(senderAddress == expectedSender, 709);
        }

        balance += amount;
        saveData(balance, ownerAddress, minterAddress, walletCode);

        // Forward notification to owner if requested
        if (forwardTon > 0) {
            var notifBody: cell = beginCell()
                .storeUint(OP_TRANSFER_NOTIFICATION, 32)
                .storeUint(queryId, 64)
                .storeCoins(amount)
                .storeAddress(fromAddress)
                .endCell();
            sendMsg(ownerAddress, forwardTon, notifBody, 1);
        }

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

    // ── OP_BURN (0x595f07bc) — explicit burn by owner ────────────────────────
    if (op == OP_BURN) {
        assert(senderAddress == ownerAddress, 705);  // only owner

        var amount: int              = inMsgBody.loadCoins();
        var responseAddress: address = inMsgBody.loadAddress();

        assert(amount > 0, 706);
        assert(balance >= amount, 707);

        balance -= amount;
        saveData(balance, ownerAddress, minterAddress, walletCode);

        // Notify minter to reduce total supply
        var burnNotif: cell = packBurnNotification(queryId, amount, ownerAddress, responseAddress);
        sendMsg(minterAddress, 0, burnNotif, 64);
        return;
    }

    throw 0xffff;  // unknown op
}

// ─── Get methods (TEP-74) ────────────────────────────────────────────────────

get fun getWalletData(): (int, address, address, cell) {
    var (balance, ownerAddress, minterAddress, walletCode) = loadData();
    return (balance, ownerAddress, minterAddress, walletCode);
}
