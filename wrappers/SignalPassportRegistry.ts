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
    TupleItemInt,
    TupleItemCell,
} from '@ton/core';
import { packTokenIdCell } from './SignalPassport';

export const RegistryOp = {
    register_passport: 0x53500004,
    set_tee_verifier: 0x10,
    change_admin: 0x11,
};

export type SignalPassportRegistryConfig = {
    adminAddress: Address;
    teeVerifierAddress: Address;
    passportCode: Cell;
    totalRegistered?: bigint;
};

export function signalPassportRegistryConfigToCell(config: SignalPassportRegistryConfig): Cell {
    return beginCell()
        .storeAddress(config.adminAddress)
        .storeAddress(config.teeVerifierAddress)
        .storeRef(config.passportCode)
        .storeUint(config.totalRegistered ?? 0n, 64)
        .endCell();
}

export class SignalPassportRegistry implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: { code: Cell; data: Cell },
    ) {}

    static createFromAddress(address: Address) {
        return new SignalPassportRegistry(address);
    }

    static createFromConfig(config: SignalPassportRegistryConfig, code: Cell, workchain = 0) {
        const data = signalPassportRegistryConfigToCell(config);
        const init = { code, data };
        return new SignalPassportRegistry(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint = toNano('0.05')) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }

    async sendRegisterPassport(
        provider: ContractProvider,
        via: Sender,
        opts: {
            ownerAddress: Address;
            nullifierHash: bigint;
            tokenId: string | Cell;
            queryLimit: number;
            sectorsMask: number;
            expiryTimestamp: number | bigint;
            responseAddress?: Address;
            queryId?: bigint;
            value?: bigint;
        },
    ) {
        const tokenIdCell = packTokenIdCell(opts.tokenId);

        await provider.internal(via, {
            value: opts.value ?? toNano('0.1'),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(RegistryOp.register_passport, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .storeAddress(opts.ownerAddress)
                .storeUint(opts.nullifierHash, 256)
                .storeRef(tokenIdCell)
                .storeUint(opts.queryLimit, 16)
                .storeUint(opts.sectorsMask, 32)
                .storeUint(BigInt(opts.expiryTimestamp), 64)
                .storeAddress(opts.responseAddress ?? opts.ownerAddress)
                .endCell(),
        });
    }

    async sendSetTeeVerifier(
        provider: ContractProvider,
        via: Sender,
        opts: { newTeeVerifier: Address; queryId?: bigint; value?: bigint },
    ) {
        await provider.internal(via, {
            value: opts.value ?? toNano('0.05'),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(RegistryOp.set_tee_verifier, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .storeAddress(opts.newTeeVerifier)
                .endCell(),
        });
    }

    async getRegistryData(provider: ContractProvider) {
        const res = await provider.get('getRegistryData', []);
        const adminAddress = res.stack.readAddress();
        const teeVerifierAddress = res.stack.readAddress();
        const passportCode = res.stack.readCell();
        const totalRegistered = res.stack.readBigNumber();
        return { adminAddress, teeVerifierAddress, passportCode, totalRegistered };
    }

    async getPassportAddress(
        provider: ContractProvider,
        opts: {
            ownerAddress: Address;
            nullifierHash: bigint;
            tokenId: string | Cell;
            queryLimit: number;
            sectorsMask: number;
            expiryTimestamp: number | bigint;
        },
    ): Promise<Address> {
        const ownerCell = beginCell().storeAddress(opts.ownerAddress).endCell();
        const tokenIdCell = packTokenIdCell(opts.tokenId);

        const res = await provider.get('getPassportAddress', [
            { type: 'slice', cell: ownerCell } as TupleItemSlice,
            { type: 'int', value: opts.nullifierHash } as TupleItemInt,
            { type: 'cell', cell: tokenIdCell } as TupleItemCell,
            { type: 'int', value: BigInt(opts.queryLimit) } as TupleItemInt,
            { type: 'int', value: BigInt(opts.sectorsMask) } as TupleItemInt,
            { type: 'int', value: BigInt(opts.expiryTimestamp) } as TupleItemInt,
        ]);
        return res.stack.readAddress();
    }
}
