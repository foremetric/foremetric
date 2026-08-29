// scripts/build_contracts.js
// Compiles all Tolk smart contracts into build/*.compiled.json and build/*/*.fif using @ton/tolk-js

const fs = require('fs');
const path = require('path');
const { runTolkCompiler } = require('@ton/tolk-js');
const { Cell } = require('@ton/core');

const CONTRACTS = [
    { name: 'ForeJettonMinter', entrypoint: 'contracts/fore_jetton_minter.tolk' },
    { name: 'ForeJettonWallet', entrypoint: 'contracts/fore_jetton_wallet.tolk' },
    { name: 'SignalPassport', entrypoint: 'contracts/signal_passport.tolk' },
    { name: 'SignalPassportRegistry', entrypoint: 'contracts/signal_passport_registry.tolk' },
];

async function main() {
    const rootDir = path.resolve(__dirname, '..');
    const buildDir = path.join(rootDir, 'build');
    if (!fs.existsSync(buildDir)) {
        fs.mkdirSync(buildDir, { recursive: true });
    }

    console.log('[*] Compiling Tolk smart contracts...');

    for (const contract of CONTRACTS) {
        const fullEntryPath = path.join(rootDir, contract.entrypoint);
        console.log(`  -> Compiling ${contract.name} (${contract.entrypoint})...`);

        const result = await runTolkCompiler({
            entrypointFileName: contract.entrypoint,
            fsReadCallback: (filePath) => {
                const resolved = path.isAbsolute(filePath) ? filePath : path.join(rootDir, filePath);
                if (fs.existsSync(resolved)) {
                    return fs.readFileSync(resolved, 'utf8');
                }
                const relativeToContract = path.join(path.dirname(fullEntryPath), filePath);
                if (fs.existsSync(relativeToContract)) {
                    return fs.readFileSync(relativeToContract, 'utf8');
                }
                throw new Error(`File not found: ${filePath}`);
            },
        });

        if (result.status !== 'ok') {
            console.error(`[!] Failed to compile ${contract.name}:`, result.message);
            if (result.stderr) console.error(result.stderr);
            process.exit(1);
        }

        const cell = Cell.fromBoc(Buffer.from(result.codeBoc64, 'base64'))[0];
        const hex = Buffer.from(result.codeBoc64, 'base64').toString('hex');
        const hash = cell.hash().toString('hex');
        const hashBase64 = cell.hash().toString('base64');

        const artifact = {
            hash,
            hashBase64,
            hex,
        };

        const outJsonPath = path.join(buildDir, `${contract.name}.compiled.json`);
        fs.writeFileSync(outJsonPath, JSON.stringify(artifact, null, 2), 'utf8');

        if (result.fiftCode) {
            const fifSubdir = path.join(buildDir, contract.name);
            if (!fs.existsSync(fifSubdir)) {
                fs.mkdirSync(fifSubdir, { recursive: true });
            }
            const fifPath = path.join(fifSubdir, `${contract.name}.fif`);
            fs.writeFileSync(fifPath, result.fiftCode, 'utf8');
        }

        console.log(`  ✓ Written ${outJsonPath} (hash: ${hash.slice(0, 12)}...)`);
    }

    console.log('[+] All contracts successfully compiled!');
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
