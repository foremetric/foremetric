// SPDX-License-Identifier: MIT
// ForeMetric $FORE Jetton 2.0 — Deploy Script (Tolk 0.13+)

import "@stdlib/deploy"

const MIN_TONS_FOR_STORAGE: int = ton("0.05");
const GAS_CONSUMPTION: int = ton("0.05");

@name(run)
fun deploy(provider: NetworkProvider) {
    var ui = provider.ui();

    var jettonParams = JettonParams {
        name: "ForeMetric",
        description: "ForeMetric — decentralized prediction market protocol on TON",
        symbol: "FORE",
        image: "https://foremetric.com/logo.png",
        decimals: 9,
        totalSupply: 1000000000 * pow(10, 9),   // 1B FORE
    };

    var jettonMaster = provider.open(
        JettonMaster.fromInit(provider.sender().address, jettonParams)
    );

    if (provider.isContractDeployed(jettonMaster.address)) {
        ui.write("ForeMetric Jetton Master already deployed at " ++ jettonMaster.address.toString());
        return;
    }

    jettonMaster.send(
        provider.sender(),
        SendParams { value: MIN_TONS_FOR_STORAGE + GAS_CONSUMPTION },
        "Deploy"
    );

    provider.waitForDeploy(jettonMaster.address);

    ui.write("ForeMetric Jetton Master deployed at " ++ jettonMaster.address.toString());
    ui.write("Total supply: " ++ jettonParams.totalSupply.toString() ++ " " ++ jettonParams.symbol);
    ui.write("Owner: " ++ provider.sender().address.toString());
}
