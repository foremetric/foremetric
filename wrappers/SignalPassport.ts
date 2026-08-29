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
    TupleItemInt,
} from '@ton/core';

export const SignalPassportOp = {
    consume_query: 0x53500001,
    revoke: 0x53500002,
    update_sectors: 0x53500003,
    excesses: 0xd53276db,
};

export const SignalPassportStatus = {
    ACTIVE: 0,
    REVOKED: 1,
    BURNED_LIMIT: 2,
    EXPIRED: 3,
};

export type SignalPassportConfig = {
    ownerAddress: Address;
    teeVerifierAddress: Address;
    nullifierHash: bigint;
    tokenId: string | Cell;
    queryLimit: number;
    remainingQueries?: number;
    sectorsMask: number;
    expiryTimestamp: number | bigint;
    status?: number;
};

export function packTokenIdCell(tokenId: string | Cell): Cell {
    if (tokenId instanceof Cell) {
        return tokenId;
    }
    return beginCell().storeStringTail(tokenId).endCell();
}

export function signalPassportConfigToCell(config: SignalPassportConfig): Cell {
    const tokenIdCell = packTokenIdCell(config.tokenId);
    const remaining = config.remainingQueries ?? config.queryLimit;
    const status = config.status ?? SignalPassportStatus.ACTIVE;

    return beginCell()
        .storeAddress(config.ownerAddress)
        .storeAddress(config.teeVerifierAddress)
        .storeUint(config.nullifierHash, 256)
        .storeRef(tokenIdCell)
        .storeUint(config.queryLimit, 16)
        .storeUint(remaining, 16)
        .storeUint(config.sectorsMask, 32)
        .storeUint(BigInt(config.expiryTimestamp), 64)
        .storeUint(status, 8)
        .endCell();
}

export class SignalPassport implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: { code: Cell; data: Cell },
    ) {}

    static createFromAddress(address: Address) {
        return new SignalPassport(address);
    }

    static createFromConfig(config: SignalPassportConfig, code: Cell, workchain = 0) {
        const data = signalPassportConfigToCell(config);
        const init = { code, data };
        return new SignalPassport(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint = toNano('0.05')) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }

    async sendConsumeQuery(
        provider: ContractProvider,
        via: Sender,
        opts: {
            requestedSectors: number;
            responseAddress?: Address;
            queryId?: bigint;
            value?: bigint;
        },
    ) {
        await provider.internal(via, {
            value: opts.value ?? toNano('0.05'),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(SignalPassportOp.consume_query, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .storeUint(opts.requestedSectors, 32)
                .storeAddress(opts.responseAddress ?? null)
                .endCell(),
        });
    }

    async sendRevoke(
        provider: ContractProvider,
        via: Sender,
        opts?: {
            responseAddress?: Address;
            queryId?: bigint;
            value?: bigint;
        },
    ) {
        await provider.internal(via, {
            value: opts?.value ?? toNano('0.05'),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(SignalPassportOp.revoke, 32)
                .storeUint(opts?.queryId ?? 0n, 64)
                .storeAddress(opts?.responseAddress ?? null)
                .endCell(),
        });
    }

    async sendUpdateSectors(
        provider: ContractProvider,
        via: Sender,
        opts: {
            newSectorsMask: number;
            responseAddress?: Address;
            queryId?: bigint;
            value?: bigint;
        },
    ) {
        await provider.internal(via, {
            value: opts.value ?? toNano('0.05'),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(SignalPassportOp.update_sectors, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .storeUint(opts.newSectorsMask, 32)
                .storeAddress(opts.responseAddress ?? null)
                .endCell(),
        });
    }

    async getPassportData(provider: ContractProvider) {
        const res = await provider.get('getPassportData', []);
        const ownerAddress = res.stack.readAddress();
        const teeVerifierAddress = res.stack.readAddress();
        const nullifierHash = res.stack.readBigNumber();
        const tokenIdCell = res.stack.readCell();
        const queryLimit = Number(res.stack.readBigNumber());
        const remainingQueries = Number(res.stack.readBigNumber());
        const sectorsMask = Number(res.stack.readBigNumber());
        const expiryTimestamp = res.stack.readBigNumber();
        const status = Number(res.stack.readBigNumber());

        const tokenId = tokenIdCell.beginParse().loadStringTail();

        return {
            ownerAddress,
            teeVerifierAddress,
            nullifierHash,
            tokenId,
            tokenIdCell,
            queryLimit,
            remainingQueries,
            sectorsMask,
            expiryTimestamp,
            status,
        };
    }

    async getNullifierHash(provider: ContractProvider): Promise<bigint> {
        const res = await provider.get('getNullifierHash', []);
        return res.stack.readBigNumber();
    }

    async getRemainingQueries(provider: ContractProvider): Promise<number> {
        const res = await provider.get('getRemainingQueries', []);
        return Number(res.stack.readBigNumber());
    }

    async getStatus(provider: ContractProvider): Promise<number> {
        const res = await provider.get('getStatus', []);
        return Number(res.stack.readBigNumber());
    }

    async isValidForQuery(
        provider: ContractProvider,
        requestedSectors: number,
    ): Promise<{ isValid: boolean; remainingQueries: number; status: number }> {
        const res = await provider.get('isValidForQuery', [
            { type: 'int', value: BigInt(requestedSectors) } as TupleItemInt,
        ]);
        const isValid = res.stack.readBigNumber() === 1n;
        const remainingQueries = Number(res.stack.readBigNumber());
        const status = Number(res.stack.readBigNumber());
        return { isValid, remainingQueries, status };
    }
}
