/**
 * tests/tee_nullifier.spec.ts — Cocoon TEE Nullifier Engine & Insight Integration Tests
 *
 * Tests the complete off-chain TEE enclave integration, cryptographic nullifier generation,
 * on-chain state verification, zero replay attack security guarantees, instant revocation,
 * sector access control, and JSON insight output formatting.
 *
 * DO NOT MOCK ASSERTIONS.
 */

import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Cell, toNano } from '@ton/core';
import { SignalPassport, SignalPassportStatus } from '../wrappers/SignalPassport';
import {
    CocoonTeeEnclave,
    SignalSector,
    ExpiryPreset,
    generateTokenId,
    computeNullifierHash,
    NullifierReplayAttackError,
    PassportRevokedError,
    PassportExpiredError,
    SectorAccessDeniedError,
    NullifierMismatchError,
    SignalPassportInsightOutput,
} from '../src/tee/nullifier_engine';
import '@ton/test-utils';

import passportCompiled from '../build/SignalPassport.compiled.json';

function getPassportCode(): Cell {
    return Cell.fromBoc(Buffer.from(passportCompiled.hex, 'hex'))[0];
}

describe('Cocoon TEE Nullifier Engine & Behavioral Insights', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let owner: SandboxContract<TreasuryContract>;
    let teeSender: SandboxContract<TreasuryContract>;
    let enclave: CocoonTeeEnclave;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        deployer = await blockchain.treasury('deployer');
        owner = await blockchain.treasury('owner');
        teeSender = await blockchain.treasury('teeSender');
        enclave = new CocoonTeeEnclave('Cocoon-TDX-v2');
    });

    describe('1. Cryptographic Token ID & Nullifier Generation', () => {
        it('generateTokenId() — outputs valid SP-XXXX-2026 format', () => {
            const id1 = generateTokenId();
            expect(id1).toMatch(/^SP-[0-9A-F]{4}-2026$/);

            const id2 = generateTokenId(42);
            expect(id2).toBe('SP-0042-2026');

            const id3 = generateTokenId(9999);
            expect(id3).toBe('SP-9999-2026');
        });

        it('computeNullifierHash() — deterministic 256-bit cryptographic nullifier', () => {
            const tokenId = 'SP-1234-2026';
            const secret = 'user_high_entropy_secret_seed';
            const salt = 'salt_ton_2026';

            const hash1 = computeNullifierHash(tokenId, secret, salt);
            const hash2 = computeNullifierHash(tokenId, secret, salt);
            expect(hash1).toBe(hash2);
            expect(typeof hash1).toBe('bigint');
            expect(hash1 > 0n).toBe(true);

            // Different secret produces different nullifier
            const hashDifferent = computeNullifierHash(tokenId, 'other_secret', salt);
            expect(hashDifferent).not.toBe(hash1);
        });
    });

    describe('2. End-to-End TEE Enclave Query Execution & JSON Insights', () => {
        let passport: SandboxContract<SignalPassport>;
        const tokenId = 'SP-8821-2026';
        const userSecret = 'secure_user_secret_entropy_pass';
        const salt = 'foremetric_tee_salt';
        const nullifierHash = computeNullifierHash(tokenId, userSecret, salt);
        const queryLimit = 2;
        const authorizedSectors = SignalSector.FINANCIAL | SignalSector.BROWSING | SignalSector.AI_INTERACTION;

        beforeEach(async () => {
            passport = blockchain.openContract(
                SignalPassport.createFromConfig(
                    {
                        ownerAddress: owner.address,
                        teeVerifierAddress: teeSender.address,
                        nullifierHash,
                        tokenId,
                        queryLimit,
                        sectorsMask: authorizedSectors,
                        expiryTimestamp: 0n,
                        status: SignalPassportStatus.ACTIVE,
                    },
                    getPassportCode(),
                ),
            );
            await passport.sendDeploy(deployer.getSender(), toNano('0.1'));
        });

        it('should execute secure query in TEE, decrement on-chain, and output compliant JSON', async () => {
            const requestedSectors = SignalSector.FINANCIAL | SignalSector.BROWSING;

            const insightOutput: SignalPassportInsightOutput = await enclave.processSecureQuery(
                passport,
                teeSender.getSender(),
                {
                    tokenId,
                    userSecret,
                    salt,
                    requestedSectors,
                    userData: {
                        FINANCIAL: { credit_score_tier: 'tier_1', dexs_used: 12 },
                        BROWSING: { daily_active_hours: 4.5 },
                    },
                },
            );

            // 1. Validate JSON Insight Schema & Compliance
            expect(insightOutput.protocol).toBe('FOREMETRIC_HUMAN_SIGNAL_INTELLIGENCE');
            expect(insightOutput.version).toBe('1.0.0');
            expect(insightOutput.token_id).toBe(tokenId);
            expect(insightOutput.nullifier_hash).toBe('0x' + nullifierHash.toString(16));
            expect(insightOutput.sectors_authorized).toEqual(
                expect.arrayContaining(['FINANCIAL', 'BROWSING', 'AI_INTERACTION']),
            );
            expect(insightOutput.sectors_requested).toEqual(
                expect.arrayContaining(['FINANCIAL', 'BROWSING']),
            );

            // 2. Validate Behavioral Insights
            expect(insightOutput.insights.FINANCIAL).toBeDefined();
            expect(insightOutput.insights.FINANCIAL.score).toBeGreaterThan(0.8);
            expect(insightOutput.insights.FINANCIAL.confidence).toBeGreaterThan(0.98);
            expect(insightOutput.insights.FINANCIAL.features.verified_human).toBe(true);
            expect(insightOutput.insights.FINANCIAL.features.no_biometrics).toBe(true);
            expect(insightOutput.insights.FINANCIAL.features.credit_score_tier).toBe('tier_1');

            expect(insightOutput.insights.BROWSING).toBeDefined();
            expect(insightOutput.insights.BROWSING.features.daily_active_hours).toBe(4.5);

            // 3. Validate TEE Hardware Attestation
            expect(insightOutput.tee_attestation.enclave_type).toBe('Cocoon-TDX-v2');
            expect(insightOutput.tee_attestation.measurement_hash).toBeDefined();
            expect(insightOutput.tee_attestation.signature.startsWith('0x')).toBe(true);
            expect(insightOutput.tee_attestation.nullifier_commitment.startsWith('0x')).toBe(true);

            // 4. Validate Query Execution Lifecycle
            expect(insightOutput.query_execution.query_number).toBe(1);
            expect(insightOutput.query_execution.query_limit).toBe(2);
            expect(insightOutput.query_execution.remaining_queries_before).toBe(2);
            expect(insightOutput.query_execution.remaining_queries_after).toBe(1);
            expect(insightOutput.query_execution.is_burned).toBe(false);
            expect(insightOutput.query_execution.status).toBe('ACTIVE');

            // 5. Verify On-Chain State was Decremented
            expect(await passport.getRemainingQueries()).toBe(1);
            expect(await passport.getStatus()).toBe(SignalPassportStatus.ACTIVE);
        });

        it('should transition to burned after consuming all queries and permanently reject replays', async () => {
            // Query 1
            await enclave.processSecureQuery(passport, teeSender.getSender(), {
                tokenId,
                userSecret,
                salt,
                requestedSectors: SignalSector.FINANCIAL,
            });
            expect(await passport.getRemainingQueries()).toBe(1);

            // Query 2 (final query)
            const secondOutput = await enclave.processSecureQuery(
                passport,
                teeSender.getSender(),
                {
                    tokenId,
                    userSecret,
                    salt,
                    requestedSectors: SignalSector.FINANCIAL,
                },
            );
            expect(secondOutput.query_execution.remaining_queries_after).toBe(0);
            expect(secondOutput.query_execution.is_burned).toBe(true);
            expect(secondOutput.query_execution.status).toBe('BURNED_LIMIT');

            // On-Chain verification
            expect(await passport.getRemainingQueries()).toBe(0);
            expect(await passport.getStatus()).toBe(SignalPassportStatus.BURNED_LIMIT);

            // Query 3: Must throw NullifierReplayAttackError
            await expect(
                enclave.processSecureQuery(passport, teeSender.getSender(), {
                    tokenId,
                    userSecret,
                    salt,
                    requestedSectors: SignalSector.FINANCIAL,
                }),
            ).rejects.toThrow(NullifierReplayAttackError);
        });
    });

    describe('3. TEE Security Boundary Violations & Error Handling', () => {
        let passport: SandboxContract<SignalPassport>;
        const tokenId = 'SP-3392-2026';
        const userSecret = 'secret_entropy_3392';
        const salt = 'foremetric_salt';
        const nullifierHash = computeNullifierHash(tokenId, userSecret, salt);

        beforeEach(async () => {
            passport = blockchain.openContract(
                SignalPassport.createFromConfig(
                    {
                        ownerAddress: owner.address,
                        teeVerifierAddress: teeSender.address,
                        nullifierHash,
                        tokenId,
                        queryLimit: 5,
                        sectorsMask: SignalSector.FINANCIAL, // only FINANCIAL
                        expiryTimestamp: 0n,
                        status: SignalPassportStatus.ACTIVE,
                    },
                    getPassportCode(),
                ),
            );
            await passport.sendDeploy(deployer.getSender(), toNano('0.1'));
        });

        it('should throw NullifierMismatchError if wrong secret is supplied to TEE', async () => {
            await expect(
                enclave.processSecureQuery(passport, teeSender.getSender(), {
                    tokenId,
                    userSecret: 'WRONG_SECRET',
                    salt,
                    requestedSectors: SignalSector.FINANCIAL,
                }),
            ).rejects.toThrow(NullifierMismatchError);
        });

        it('should throw SectorAccessDeniedError if requesting unauthorized sector', async () => {
            await expect(
                enclave.processSecureQuery(passport, teeSender.getSender(), {
                    tokenId,
                    userSecret,
                    salt,
                    requestedSectors: SignalSector.HEALTH, // Not authorized
                }),
            ).rejects.toThrow(SectorAccessDeniedError);
        });

        it('should throw PassportRevokedError after owner revokes', async () => {
            await passport.sendRevoke(owner.getSender());

            await expect(
                enclave.processSecureQuery(passport, teeSender.getSender(), {
                    tokenId,
                    userSecret,
                    salt,
                    requestedSectors: SignalSector.FINANCIAL,
                }),
            ).rejects.toThrow(PassportRevokedError);
        });
    });
});
