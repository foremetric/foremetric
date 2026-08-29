// src/tee/nullifier_engine.ts — Cocoon TEE Cryptographic Nullifier & Insight Generation Engine
//
// Implements the off-chain/TEE enclave module that verifies Signal Passport nullifiers,
// checks state before each query, validates sector permissions & replay resistance,
// generates cryptographic TDX/TrustZone attestations, and formats standard JSON insight outputs.

import crypto from 'crypto';
import { Address, Cell, Sender } from '@ton/core';
import { SignalPassportStatus } from '../../wrappers/SignalPassport';

// ─── Behavioral Sectors Bitmask ───────────────────────────────────────────────
export enum SignalSector {
    FINANCIAL = 1 << 0,       // 0x01
    BROWSING = 1 << 1,        // 0x02
    SOCIAL = 1 << 2,          // 0x04
    GAMING = 1 << 3,          // 0x08
    HEALTH = 1 << 4,          // 0x10
    AI_INTERACTION = 1 << 5,  // 0x20
    ECOMMERCE = 1 << 6,       // 0x40
    LOCATION = 1 << 7,        // 0x80
}

export const ALL_SECTORS_MASK =
    SignalSector.FINANCIAL |
    SignalSector.BROWSING |
    SignalSector.SOCIAL |
    SignalSector.GAMING |
    SignalSector.HEALTH |
    SignalSector.AI_INTERACTION |
    SignalSector.ECOMMERCE |
    SignalSector.LOCATION;

export const SECTOR_NAMES: Record<number, string> = {
    [SignalSector.FINANCIAL]: 'FINANCIAL',
    [SignalSector.BROWSING]: 'BROWSING',
    [SignalSector.SOCIAL]: 'SOCIAL',
    [SignalSector.GAMING]: 'GAMING',
    [SignalSector.HEALTH]: 'HEALTH',
    [SignalSector.AI_INTERACTION]: 'AI_INTERACTION',
    [SignalSector.ECOMMERCE]: 'ECOMMERCE',
    [SignalSector.LOCATION]: 'LOCATION',
};

// ─── Expiry Presets ───────────────────────────────────────────────────────────
export const ExpiryPreset = {
    HOURS_24: 86400,
    DAYS_7: 604800,
    DAYS_30: 2592000,
    UNLIMITED: 0,
} as const;

// ─── Error Classes ────────────────────────────────────────────────────────────
export class NullifierReplayAttackError extends Error {
    constructor(message = 'Zero Replay Attack Prevention: Nullifier has been burned or exhausted.') {
        super(message);
        this.name = 'NullifierReplayAttackError';
    }
}

export class PassportRevokedError extends Error {
    constructor(message = 'Passport has been revoked on-chain by the owner.') {
        super(message);
        this.name = 'PassportRevokedError';
    }
}

export class PassportExpiredError extends Error {
    constructor(message = 'Passport has expired on-chain.') {
        super(message);
        this.name = 'PassportExpiredError';
    }
}

export class SectorAccessDeniedError extends Error {
    constructor(requested: number, authorized: number) {
        super(
            `Access Denied: Requested sectors (0x${requested.toString(16)}) exceed authorized permissions (0x${authorized.toString(16)})`,
        );
        this.name = 'SectorAccessDeniedError';
    }
}

export class NullifierMismatchError extends Error {
    constructor(message = 'Nullifier hash does not match on-chain registered state.') {
        super(message);
        this.name = 'NullifierMismatchError';
    }
}

// ─── Contract Interface for Opened/Sandbox Contract ───────────────────────────

export interface ISignalPassportContract {
    getPassportData(): Promise<{
        ownerAddress: Address;
        teeVerifierAddress: Address;
        nullifierHash: bigint;
        tokenId: string;
        tokenIdCell: Cell;
        queryLimit: number;
        remainingQueries: number;
        sectorsMask: number;
        expiryTimestamp: bigint;
        status: number;
    }>;
    isValidForQuery(requestedSectors: number): Promise<{
        isValid: boolean;
        remainingQueries: number;
        status: number;
    }>;
    sendConsumeQuery(
        via: Sender,
        opts: {
            requestedSectors: number;
            responseAddress?: Address;
            queryId?: bigint;
            value?: bigint;
        },
    ): Promise<any>;
    getRemainingQueries(): Promise<number>;
    getStatus(): Promise<number>;
}

// ─── Types & Interfaces ───────────────────────────────────────────────────────

export interface SectorInsight {
    score: number;
    confidence: number;
    signals_processed: number;
    entropy: number;
    features: Record<string, number | string | boolean>;
}

export interface TeeAttestation {
    enclave_type: 'Intel-TDX' | 'ARM-TrustZone' | 'Cocoon-TDX-v2';
    measurement_hash: string;
    timestamp: number;
    nullifier_commitment: string;
    signature: string;
}

export interface SignalPassportInsightOutput {
    protocol: 'FOREMETRIC_HUMAN_SIGNAL_INTELLIGENCE';
    version: '1.0.0';
    token_id: string;
    nullifier_hash: string;
    timestamp: number;
    sectors_authorized: string[];
    sectors_requested: string[];
    insights: Record<string, SectorInsight>;
    tee_attestation: TeeAttestation;
    query_execution: {
        query_number: number;
        query_limit: number;
        remaining_queries_before: number;
        remaining_queries_after: number;
        is_burned: boolean;
        status: 'ACTIVE' | 'REVOKED' | 'BURNED_LIMIT' | 'EXPIRED';
    };
}

// ─── Cryptographic Nullifier Generator ────────────────────────────────────────

export function generateTokenId(suffix?: string | number): string {
    if (suffix !== undefined) {
        const padded = String(suffix).padStart(4, '0').slice(-4);
        return `SP-${padded}-2026`;
    }
    const rand = crypto.randomBytes(2).toString('hex').toUpperCase();
    return `SP-${rand}-2026`;
}

export function computeNullifierHash(
    tokenId: string,
    userSecret: string | Buffer,
    salt?: string | Buffer,
): bigint {
    const hash = crypto.createHash('sha256');
    hash.update(Buffer.from(tokenId, 'utf8'));
    hash.update(typeof userSecret === 'string' ? Buffer.from(userSecret, 'utf8') : userSecret);
    if (salt) {
        hash.update(typeof salt === 'string' ? Buffer.from(salt, 'utf8') : salt);
    }
    const digest = hash.digest('hex');
    return BigInt('0x' + digest);
}

export function maskToSectorNames(mask: number): string[] {
    const list: string[] = [];
    for (const [bitStr, name] of Object.entries(SECTOR_NAMES)) {
        const bit = Number(bitStr);
        if ((mask & bit) === bit) {
            list.push(name);
        }
    }
    return list;
}

// ─── Cocoon TEE Enclave Simulation & Verification Engine ──────────────────────

export class CocoonTeeEnclave {
    readonly enclaveType: 'Intel-TDX' | 'ARM-TrustZone' | 'Cocoon-TDX-v2';
    readonly measurementHash: string;
    private readonly privateKey: Buffer;

    constructor(
        enclaveType: 'Intel-TDX' | 'ARM-TrustZone' | 'Cocoon-TDX-v2' = 'Cocoon-TDX-v2',
        secretKey?: Buffer,
    ) {
        this.enclaveType = enclaveType;
        this.privateKey = secretKey ?? crypto.randomBytes(32);
        this.measurementHash = crypto
            .createHash('sha256')
            .update(`COCOON_TDX_MEASUREMENT_${enclaveType}`)
            .digest('hex');
    }

    createAttestation(nullifierHash: bigint, tokenId: string, timestamp: number): TeeAttestation {
        const commitment = crypto
            .createHash('sha256')
            .update(`${tokenId}:${nullifierHash.toString(16)}:${timestamp}`)
            .digest('hex');

        const signature = crypto
            .createHmac('sha256', this.privateKey)
            .update(`${this.measurementHash}:${commitment}:${timestamp}`)
            .digest('hex');

        return {
            enclave_type: this.enclaveType,
            measurement_hash: this.measurementHash,
            timestamp,
            nullifier_commitment: '0x' + commitment,
            signature: '0x' + signature,
        };
    }

    generateSectorInsights(
        requestedSectors: number,
        userData?: Record<string, any>,
    ): Record<string, SectorInsight> {
        const insights: Record<string, SectorInsight> = {};
        for (const [bitStr, name] of Object.entries(SECTOR_NAMES)) {
            const bit = Number(bitStr);
            if ((requestedSectors & bit) === bit) {
                insights[name] = {
                    score: 0.85 + (crypto.randomBytes(1)[0] / 255) * 0.14,
                    confidence: 0.985 + (crypto.randomBytes(1)[0] / 255) * 0.014,
                    signals_processed: 120 + (crypto.randomBytes(1)[0] % 80),
                    entropy: 0.72 + (crypto.randomBytes(1)[0] / 255) * 0.25,
                    features: {
                        verified_human: true,
                        no_biometrics: true,
                        privacy_preserved: true,
                        synthetic_contamination_detected: false,
                        ...(userData?.[name] ?? {}),
                    },
                };
            }
        }
        return insights;
    }

    async verifyNullifierState(
        passportContract: ISignalPassportContract,
        requestedSectors: number,
    ): Promise<{
        isValid: boolean;
        remainingQueries: number;
        status: number;
        data: Awaited<ReturnType<ISignalPassportContract['getPassportData']>>;
    }> {
        const data = await passportContract.getPassportData();
        const check = await passportContract.isValidForQuery(requestedSectors);

        return {
            isValid: check.isValid,
            remainingQueries: check.remainingQueries,
            status: check.status,
            data,
        };
    }

    async processSecureQuery(
        passportContract: ISignalPassportContract,
        teeSender: Sender,
        opts: {
            tokenId: string;
            userSecret: string | Buffer;
            salt?: string | Buffer;
            requestedSectors: number;
            userData?: Record<string, any>;
            responseAddress?: Address;
            queryId?: bigint;
        },
    ): Promise<SignalPassportInsightOutput> {
        // 1. Verify nullifier hash derivation
        const derivedNullifier = computeNullifierHash(opts.tokenId, opts.userSecret, opts.salt);

        // 2. Pre-query TEE verification of on-chain state
        const verification = await this.verifyNullifierState(
            passportContract,
            opts.requestedSectors,
        );

        if (verification.data.nullifierHash !== derivedNullifier) {
            throw new NullifierMismatchError(
                `Derived nullifier 0x${derivedNullifier.toString(16)} != on-chain 0x${verification.data.nullifierHash.toString(16)}`,
            );
        }

        if (verification.status === SignalPassportStatus.REVOKED) {
            throw new PassportRevokedError();
        }

        if (
            verification.status === SignalPassportStatus.BURNED_LIMIT ||
            verification.remainingQueries <= 0
        ) {
            throw new NullifierReplayAttackError(
                `Replay Attack Prevention: Nullifier exhausted (remaining: ${verification.remainingQueries}, status: ${verification.status})`,
            );
        }

        if (verification.status === SignalPassportStatus.EXPIRED) {
            throw new PassportExpiredError();
        }

        if ((opts.requestedSectors & verification.data.sectorsMask) !== opts.requestedSectors) {
            throw new SectorAccessDeniedError(
                opts.requestedSectors,
                verification.data.sectorsMask,
            );
        }

        const remainingBefore = verification.remainingQueries;
        const queryNumber = verification.data.queryLimit - remainingBefore + 1;
        const nowSec = Math.floor(Date.now() / 1000);

        // 3. Compute verified behavioral insights inside enclave
        const insights = this.generateSectorInsights(opts.requestedSectors, opts.userData);

        // 4. Generate hardware enclave cryptographic attestation
        const attestation = this.createAttestation(derivedNullifier, opts.tokenId, nowSec);

        // 5. Submit on-chain consumption transaction to decrement counter
        await passportContract.sendConsumeQuery(teeSender, {
            requestedSectors: opts.requestedSectors,
            responseAddress: opts.responseAddress,
            queryId: opts.queryId ?? BigInt(queryNumber),
        });

        // 6. Post-query state check
        const remainingAfter = await passportContract.getRemainingQueries();
        const postStatus = await passportContract.getStatus();

        const statusMap: Record<number, 'ACTIVE' | 'REVOKED' | 'BURNED_LIMIT' | 'EXPIRED'> = {
            [SignalPassportStatus.ACTIVE]: 'ACTIVE',
            [SignalPassportStatus.REVOKED]: 'REVOKED',
            [SignalPassportStatus.BURNED_LIMIT]: 'BURNED_LIMIT',
            [SignalPassportStatus.EXPIRED]: 'EXPIRED',
        };

        const result: SignalPassportInsightOutput = {
            protocol: 'FOREMETRIC_HUMAN_SIGNAL_INTELLIGENCE',
            version: '1.0.0',
            token_id: opts.tokenId,
            nullifier_hash: '0x' + derivedNullifier.toString(16),
            timestamp: nowSec,
            sectors_authorized: maskToSectorNames(verification.data.sectorsMask),
            sectors_requested: maskToSectorNames(opts.requestedSectors),
            insights,
            tee_attestation: attestation,
            query_execution: {
                query_number: queryNumber,
                query_limit: verification.data.queryLimit,
                remaining_queries_before: remainingBefore,
                remaining_queries_after: remainingAfter,
                is_burned: remainingAfter === 0 || postStatus === SignalPassportStatus.BURNED_LIMIT,
                status: statusMap[postStatus] ?? 'ACTIVE',
            },
        };

        return result;
    }
}
