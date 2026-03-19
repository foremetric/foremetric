import "@stdlib/deploy";

const minTonsForStorage = ton("0.05");
const gasConsumption = ton("0.05");

export async function run(provider: NetworkProvider) {
    const ui = provider.ui();

    const jettonParams = {
        name: "FORE Protocol",
        description: "Prediction market protocol token",
        symbol: "FORE",
        image: "https://fore-protocol.com/logo.png",
        decimals: 9,
        totalSupply: 1000000000n * (10n ** 9n), // 1 billion tokens
    };

    const jettonMaster = provider.open(await JettonMaster.fromInit(
        provider.sender().address!,
        jettonParams
    ));

    if (await provider.isContractDeployed(jettonMaster.address)) {
        ui.write(`Jetton Master already deployed at ${jettonMaster.address}`);
        return;
    }

    await jettonMaster.send(
        provider.sender(),
        {
            value: minTonsForStorage + gasConsumption,
        },
        "Deploy"
    );

    await provider.waitForDeploy(jettonMaster.address);

    ui.write(`Jetton Master deployed at ${jettonMaster.address}`);
    ui.write(`Total supply: ${jettonParams.totalSupply} ${jettonParams.symbol}`);
    ui.write(`Owner: ${provider.sender().address}`);
}