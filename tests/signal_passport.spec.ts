/**
 * tests/signal_passport.spec.ts — Signal Passport Smart Contract Tests
 *
 * Comprehensive tests for SignalPassport and SignalPassportRegistry contracts on TON blockchain.
 * Uses @ton/sandbox for in-memory TON blockchain execution with real compiled BOCs.
 *
 * DO NOT MOCK ASSERTIONS.
 */

import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Cell, toNano, beginCell } from '@ton/core';
import { SignalPassport, SignalPassportStatus, SignalPassportOp } from '../wrappers/SignalPassport';
import { SignalPassportRegistry, RegistryOp } from '../wrappers/SignalPassportRegistry';
import {
    SignalSector,
    ExpiryPreset,
    generateTokenId,
    computeNullifierHash,
} from '../src/tee/nullifier_engine';
import '@ton/test-utils';

import passportCompiled from '../build/SignalPassport.compiled.json';
import registryCompiled from '../build/SignalPassportRegistry.compiled.json';

function getPassportCode(): Cell {
    return Cell.fromBoc(Buffer.from(passportCompiled.hex, 'hex'))[0];
}

function getRegistryCode(): Cell {
    return Cell.fromBoc(Buffer.from(registryCompiled.hex, 'hex'))[0];
}

describe('Signal Passport — Smart Contract Test Suite', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let owner: SandboxContract<TreasuryContract>;
    let teeVerifier: SandboxContract<TreasuryContract>;
    let attacker: SandboxContract<TreasuryContract>;
    let passport: SandboxContract<SignalPassport>;

    const tokenId = 'SP-4821-2026';
    const userSecret = 'secret_user_entropy_2026_x89';
    const nullifierHash = computeNullifierHash(tokenId, userSecret);
    const queryLimit = 3;
    const sectorsMask = SignalSector.FINANCIAL | SignalSector.BROWSING | SignalSector.SOCIAL; // 0x07

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        deployer = await blockchain.treasury('deployer');
        owner = await blockchain.treasury('owner');
        teeVerifier = await blockchain.treasury('teeVerifier');
        attacker = await blockchain.treasury('attacker');

        passport = blockchain.openContract(
            SignalPassport.createFromConfig(
                {
                    ownerAddress: owner.address,
                    teeVerifierAddress: teeVerifier.address,
                    nullifierHash,
                    tokenId,
                    queryLimit,
                    sectorsMask,
                    expiryTimestamp: 0n, // unlimited
                    status: SignalPassportStatus.ACTIVE,
                },
                getPassportCode(),
            ),
        );
    });

    describe('1. Deployment & Initialization', () => {
        it('should deploy SignalPassport contract successfully', async () => {
            const deployResult = await passport.sendDeploy(deployer.getSender(), toNano('0.1'));
            expect(deployResult.transactions).toHaveTransaction({
                from: deployer.address,
                to: passport.address,
                deploy: true,
                success: true,
            });
        });

        it('getPassportData() — returns correct initial state', async () => {
            await passport.sendDeploy(deployer.getSender(), toNano('0.1'));

            const data = await passport.getPassportData();
            expect(data.ownerAddress.equals(owner.address)).toBe(true);
            expect(data.teeVerifierAddress.equals(teeVerifier.address)).toBe(true);
            expect(data.nullifierHash).toBe(nullifierHash);
            expect(data.tokenId).toBe(tokenId);
            expect(data.queryLimit).toBe(queryLimit);
            expect(data.remainingQueries).toBe(queryLimit);
            expect(data.sectorsMask).toBe(sectorsMask);
            expect(data.expiryTimestamp).toBe(0n);
            expect(data.status).toBe(SignalPassportStatus.ACTIVE);
        });

        it('getNullifierHash() & getRemainingQueries() & getStatus() get methods', async () => {
            await passport.sendDeploy(deployer.getSender(), toNano('0.1'));

            expect(await passport.getNullifierHash()).toBe(nullifierHash);
            expect(await passport.getRemainingQueries()).toBe(queryLimit);
            expect(await passport.getStatus()).toBe(SignalPassportStatus.ACTIVE);
        });
    });

    describe('2. Cocoon TEE Query Consumption & Counter Decrement', () => {
        beforeEach(async () => {
            await passport.sendDeploy(deployer.getSender(), toNano('0.1'));
        });

        it('should allow authorized TEE verifier to consume queries and decrement counter', async () => {
            // Query 1: FINANCIAL
            const res1 = await passport.sendConsumeQuery(teeVerifier.getSender(), {
                requestedSectors: SignalSector.FINANCIAL,
                queryId: 1n,
            });
            expect(res1.transactions).toHaveTransaction({
                from: teeVerifier.address,
                to: passport.address,
                success: true,
            });
            expect(await passport.getRemainingQueries()).toBe(2);
            expect(await passport.getStatus()).toBe(SignalPassportStatus.ACTIVE);

            // Query 2: BROWSING
            const res2 = await passport.sendConsumeQuery(teeVerifier.getSender(), {
                requestedSectors: SignalSector.BROWSING,
                queryId: 2n,
            });
            expect(res2.transactions).toHaveTransaction({
                from: teeVerifier.address,
                to: passport.address,
                success: true,
            });
            expect(await passport.getRemainingQueries()).toBe(1);
            expect(await passport.getStatus()).toBe(SignalPassportStatus.ACTIVE);

            // Query 3: FINANCIAL | SOCIAL (last remaining query)
            const res3 = await passport.sendConsumeQuery(teeVerifier.getSender(), {
                requestedSectors: SignalSector.FINANCIAL | SignalSector.SOCIAL,
                queryId: 3n,
            });
            expect(res3.transactions).toHaveTransaction({
                from: teeVerifier.address,
                to: passport.address,
                success: true,
            });

            // After 3rd query: counter is 0 and status is BURNED_LIMIT
            expect(await passport.getRemainingQueries()).toBe(0);
            expect(await passport.getStatus()).toBe(SignalPassportStatus.BURNED_LIMIT);
        });

        it('isValidForQuery() — reports active during valid queries and false when exhausted', async () => {
            const check1 = await passport.isValidForQuery(SignalSector.FINANCIAL);
            expect(check1.isValid).toBe(true);
            expect(check1.remainingQueries).toBe(3);
            expect(check1.status).toBe(SignalPassportStatus.ACTIVE);

            // Consume all 3 queries
            for (let i = 0; i < 3; i++) {
                await passport.sendConsumeQuery(teeVerifier.getSender(), {
                    requestedSectors: SignalSector.FINANCIAL,
                });
            }

            const checkAfter = await passport.isValidForQuery(SignalSector.FINANCIAL);
            expect(checkAfter.isValid).toBe(false);
            expect(checkAfter.remainingQueries).toBe(0);
            expect(checkAfter.status).toBe(SignalPassportStatus.BURNED_LIMIT);
        });
    });

    describe('3. Zero Replay Attack Prevention (Permanent Burn)', () => {
        beforeEach(async () => {
            await passport.sendDeploy(deployer.getSender(), toNano('0.1'));
            // Exhaust all queries
            for (let i = 0; i < queryLimit; i++) {
                await passport.sendConsumeQuery(teeVerifier.getSender(), {
                    requestedSectors: SignalSector.FINANCIAL,
                });
            }
        });

        it('should REJECT 4th query attempt after burn (Zero Replay Attack guarantee)', async () => {
            expect(await passport.getRemainingQueries()).toBe(0);
            expect(await passport.getStatus()).toBe(SignalPassportStatus.BURNED_LIMIT);

            const replayAttempt = await passport.sendConsumeQuery(teeVerifier.getSender(), {
                requestedSectors: SignalSector.FINANCIAL,
                queryId: 4n,
            });

            // Must fail on-chain
            expect(replayAttempt.transactions).toHaveTransaction({
                from: teeVerifier.address,
                to: passport.address,
                success: false,
                exitCode: 802, // ERR_NOT_ACTIVE
            });

            // State remains permanently burned
            expect(await passport.getRemainingQueries()).toBe(0);
            expect(await passport.getStatus()).toBe(SignalPassportStatus.BURNED_LIMIT);
        });
    });

    describe('4. Instant Revocation by Owner', () => {
        beforeEach(async () => {
            await passport.sendDeploy(deployer.getSender(), toNano('0.1'));
        });

        it('should allow owner to instantly revoke passport on-chain at any time', async () => {
            const revokeRes = await passport.sendRevoke(owner.getSender(), {
                queryId: 100n,
            });
            expect(revokeRes.transactions).toHaveTransaction({
                from: owner.address,
                to: passport.address,
                success: true,
            });

            expect(await passport.getStatus()).toBe(SignalPassportStatus.REVOKED);
            expect(await passport.getRemainingQueries()).toBe(0);
        });

        it('should NOT allow non-owner/attacker to revoke passport (ERR_UNAUTHORIZED: 801)', async () => {
            const attackRes = await passport.sendRevoke(attacker.getSender(), {
                queryId: 101n,
            });
            expect(attackRes.transactions).toHaveTransaction({
                from: attacker.address,
                to: passport.address,
                success: false,
                exitCode: 801,
            });

            // Status remains ACTIVE
            expect(await passport.getStatus()).toBe(SignalPassportStatus.ACTIVE);
            expect(await passport.getRemainingQueries()).toBe(queryLimit);
        });

        it('should REJECT any query consumption after owner revocation', async () => {
            await passport.sendRevoke(owner.getSender());

            const queryRes = await passport.sendConsumeQuery(teeVerifier.getSender(), {
                requestedSectors: SignalSector.FINANCIAL,
            });
            expect(queryRes.transactions).toHaveTransaction({
                from: teeVerifier.address,
                to: passport.address,
                success: false,
                exitCode: 802, // ERR_NOT_ACTIVE
            });
        });
    });

    describe('5. Sector Access Control & Configuration', () => {
        beforeEach(async () => {
            await passport.sendDeploy(deployer.getSender(), toNano('0.1'));
        });

        it('should REJECT query requesting unauthorized sector (ERR_SECTOR_NOT_ALLOWED: 805)', async () => {
            // sectorsMask is FINANCIAL | BROWSING | SOCIAL (0x07). Requesting HEALTH (0x10) should fail.
            const res = await passport.sendConsumeQuery(teeVerifier.getSender(), {
                requestedSectors: SignalSector.HEALTH,
            });
            expect(res.transactions).toHaveTransaction({
                from: teeVerifier.address,
                to: passport.address,
                success: false,
                exitCode: 805,
            });

            // Counter must not be decremented
            expect(await passport.getRemainingQueries()).toBe(queryLimit);
        });

        it('should allow owner to update sector configuration permissions', async () => {
            const newMask = SignalSector.FINANCIAL | SignalSector.HEALTH; // 0x11
            const updateRes = await passport.sendUpdateSectors(owner.getSender(), {
                newSectorsMask: newMask,
            });
            expect(updateRes.transactions).toHaveTransaction({
                from: owner.address,
                to: passport.address,
                success: true,
            });

            const data = await passport.getPassportData();
            expect(data.sectorsMask).toBe(newMask);

            // Now HEALTH query succeeds
            const healthQuery = await passport.sendConsumeQuery(teeVerifier.getSender(), {
                requestedSectors: SignalSector.HEALTH,
            });
            expect(healthQuery.transactions).toHaveTransaction({
                from: teeVerifier.address,
                to: passport.address,
                success: true,
            });
        });

        it('should NOT allow non-owner to update sector configuration (ERR_UNAUTHORIZED: 801)', async () => {
            const res = await passport.sendUpdateSectors(attacker.getSender(), {
                newSectorsMask: SignalSector.HEALTH,
            });
            expect(res.transactions).toHaveTransaction({
                from: attacker.address,
                to: passport.address,
                success: false,
                exitCode: 801,
            });
        });
    });

    describe('6. Security & Authorization Checks', () => {
        beforeEach(async () => {
            await passport.sendDeploy(deployer.getSender(), toNano('0.1'));
        });

        it('should REJECT query consumption from unauthorized attacker (ERR_UNAUTHORIZED: 801)', async () => {
            const res = await passport.sendConsumeQuery(attacker.getSender(), {
                requestedSectors: SignalSector.FINANCIAL,
            });
            expect(res.transactions).toHaveTransaction({
                from: attacker.address,
                to: passport.address,
                success: false,
                exitCode: 801,
            });

            expect(await passport.getRemainingQueries()).toBe(queryLimit);
        });
    });

    describe('7. SignalPassportRegistry (Registration & Deterministic Deployment)', () => {
        let registry: SandboxContract<SignalPassportRegistry>;

        beforeEach(async () => {
            registry = blockchain.openContract(
                SignalPassportRegistry.createFromConfig(
                    {
                        adminAddress: deployer.address,
                        teeVerifierAddress: teeVerifier.address,
                        passportCode: getPassportCode(),
                        totalRegistered: 0n,
                    },
                    getRegistryCode(),
                ),
            );
            await registry.sendDeploy(deployer.getSender(), toNano('0.1'));
        });

        it('should deploy registry and return initial data', async () => {
            const data = await registry.getRegistryData();
            expect(data.adminAddress.equals(deployer.address)).toBe(true);
            expect(data.teeVerifierAddress.equals(teeVerifier.address)).toBe(true);
            expect(data.totalRegistered).toBe(0n);
        });

        it('should register passport and deploy with deterministic address', async () => {
            const regTokenId = 'SP-9901-2026';
            const regNullifier = computeNullifierHash(regTokenId, 'user_entropy_9901');
            const regLimit = 10;
            const regSectors = SignalSector.FINANCIAL | SignalSector.GAMING;
            const regExpiry = 0n;

            const expectedAddress = await registry.getPassportAddress({
                ownerAddress: owner.address,
                nullifierHash: regNullifier,
                tokenId: regTokenId,
                queryLimit: regLimit,
                sectorsMask: regSectors,
                expiryTimestamp: regExpiry,
            });

            const regRes = await registry.sendRegisterPassport(owner.getSender(), {
                ownerAddress: owner.address,
                nullifierHash: regNullifier,
                tokenId: regTokenId,
                queryLimit: regLimit,
                sectorsMask: regSectors,
                expiryTimestamp: regExpiry,
                value: toNano('0.15'),
            });

            expect(regRes.transactions).toHaveTransaction({
                from: registry.address,
                to: expectedAddress,
                deploy: true,
                success: true,
            });

            const regData = await registry.getRegistryData();
            expect(regData.totalRegistered).toBe(1n);

            // Verify the newly deployed passport contract instance
            const deployedPassport = blockchain.openContract(
                SignalPassport.createFromAddress(expectedAddress),
            );
            const pData = await deployedPassport.getPassportData();
            expect(pData.ownerAddress.equals(owner.address)).toBe(true);
            expect(pData.teeVerifierAddress.equals(teeVerifier.address)).toBe(true);
            expect(pData.nullifierHash).toBe(regNullifier);
            expect(pData.tokenId).toBe(regTokenId);
            expect(pData.queryLimit).toBe(regLimit);
            expect(pData.remainingQueries).toBe(regLimit);
            expect(pData.status).toBe(SignalPassportStatus.ACTIVE);
        });

        it('should REJECT invalid query limit < 1 or > 9999 (ERR_INVALID_LIMIT: 806)', async () => {
            // Limit 0
            const resLow = await registry.sendRegisterPassport(owner.getSender(), {
                ownerAddress: owner.address,
                nullifierHash: 12345n,
                tokenId: 'SP-0000-2026',
                queryLimit: 0,
                sectorsMask: 1,
                expiryTimestamp: 0n,
            });
            expect(resLow.transactions).toHaveTransaction({
                from: owner.address,
                to: registry.address,
                success: false,
                exitCode: 806,
            });

            // Limit 10,000
            const resHigh = await registry.sendRegisterPassport(owner.getSender(), {
                ownerAddress: owner.address,
                nullifierHash: 12345n,
                tokenId: 'SP-9999-2026',
                queryLimit: 10000,
                sectorsMask: 1,
                expiryTimestamp: 0n,
            });
            expect(resHigh.transactions).toHaveTransaction({
                from: owner.address,
                to: registry.address,
                success: false,
                exitCode: 806,
            });
        });
    });
});
