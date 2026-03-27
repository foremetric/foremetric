import {
    Address,
    beginCell,
    Cell,
    Contract,
    contractAddress,
    ContractProvider,
    Sender,
    SendMode,
    toNano,
    TupleItemSlice,
} from '@ton/core';

// Op codes (matching fore_jetton_minter.tolk constants)
export const Op = {
    mint: 0x1,
    change_admin: 0x4,
    change_content: 0x5,
    internal_transfer: 0x178d4519,
    burn_notification: 0x7bdd97de,
    excesses: 0xd53276db,
};

export type ForeJettonMinterConfig = {
    totalSupply: bigint;
    mintable: boolean;
    adminAddress: Address;
    content: Cell;
    jettonWalletCode: Cell;
};

export function foreJettonMinterConfigToCell(config: ForeJettonMinterConfig): Cell {
    return beginCell()
        .storeCoins(config.totalSupply)
        .storeUint(config.mintable ? 1 : 0, 1)
        .storeAddress(config.adminAddress)
        .storeRef(config.content)
        .storeRef(config.jettonWalletCode)
        .endCell();
}

export class ForeJettonMinter implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: { code: Cell; data: Cell },
    ) {}

    static createFromAddress(address: Address) {
        return new ForeJettonMinter(address);
    }

    static createFromConfig(config: ForeJettonMinterConfig, code: Cell, workchain = 0) {
        const data = foreJettonMinterConfigToCell(config);
        const init = { code, data };
        return new ForeJettonMinter(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }

    async sendMint(
        provider: ContractProvider,
        via: Sender,
        opts: {
            toAddress: Address;
            amount: bigint;
            forwardTon?: bigint;
            queryId?: bigint;
            value?: bigint;
        },
    ) {
        await provider.internal(via, {
            value: opts.value ?? toNano('0.3'),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(Op.mint, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .storeAddress(opts.toAddress)
                .storeCoins(opts.amount)
                .storeCoins(opts.forwardTon ?? 0n)
                .endCell(),
        });
    }

    async sendChangeAdmin(
        provider: ContractProvider,
        via: Sender,
        opts: { newAdmin: Address; queryId?: bigint; value?: bigint },
    ) {
        await provider.internal(via, {
            value: opts.value ?? toNano('0.05'),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(Op.change_admin, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .storeAddress(opts.newAdmin)
                .endCell(),
        });
    }

    async getJettonData(provider: ContractProvider) {
        const res = await provider.get('getJettonData', []);
        const totalSupply = res.stack.readBigNumber();
        const mintable = res.stack.readBigNumber();
        const adminAddress = res.stack.readAddress();
        const content = res.stack.readCell();
        const walletCode = res.stack.readCell();
        return { totalSupply, mintable, adminAddress, content, walletCode };
    }

    async getWalletAddress(provider: ContractProvider, ownerAddress: Address): Promise<Address> {
        const ownerCell = beginCell().storeAddress(ownerAddress).endCell();
        const res = await provider.get('getWalletAddress', [
            { type: 'slice', cell: ownerCell } as TupleItemSlice,
        ]);
        return res.stack.readAddress();
    }
}
