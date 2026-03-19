import {
    Address,
    beginCell,
    Cell,
    Contract,
    ContractProvider,
    Sender,
    SendMode,
    toNano,
} from '@ton/core';

// Op codes (matching fore_jetton_wallet.tolk constants)
export const WalletOp = {
    transfer: 0xf8a7ea5,
    internal_transfer: 0x178d4519,
    burn: 0x595f07bc,
    transfer_notification: 0x7362d09c,
    excesses: 0xd53276db,
};

export class ForeJettonWallet implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: { code: Cell; data: Cell },
    ) {}

    static createFromAddress(address: Address) {
        return new ForeJettonWallet(address);
    }

    async sendTransfer(
        provider: ContractProvider,
        via: Sender,
        opts: {
            amount: bigint;
            destination: Address;
            responseAddress?: Address;
            forwardTonAmount?: bigint;
            queryId?: bigint;
            value?: bigint;
        },
    ) {
        const fwdTon = opts.forwardTonAmount ?? 0n;
        await provider.internal(via, {
            value: opts.value ?? toNano('0.1'),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(WalletOp.transfer, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .storeCoins(opts.amount)
                .storeAddress(opts.destination)
                .storeAddress(opts.responseAddress ?? opts.destination)
                .storeUint(0, 1)   // no custom_payload
                .storeCoins(fwdTon)
                .storeUint(0, 1)   // no forward_payload
                .endCell(),
        });
    }

    async sendBurn(
        provider: ContractProvider,
        via: Sender,
        opts: {
            amount: bigint;
            responseAddress?: Address;
            queryId?: bigint;
            value?: bigint;
        },
    ) {
        await provider.internal(via, {
            value: opts.value ?? toNano('0.1'),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(WalletOp.burn, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .storeCoins(opts.amount)
                .storeAddress(opts.responseAddress ?? null)
                .endCell(),
        });
    }

    async getWalletData(provider: ContractProvider) {
        const res = await provider.get('getWalletData', []);
        const balance = res.stack.readBigNumber();
        const ownerAddress = res.stack.readAddress();
        const minterAddress = res.stack.readAddress();
        const walletCode = res.stack.readCell();
        return { balance, ownerAddress, minterAddress, walletCode };
    }
}
