
async function deploySlotMachine() {
    const SlotMachine = await ethers.getContractFactory("SlotMachine");
    const machine = await SlotMachine.deploy(
        
    )
}

async function main() {
    let slotAddress = await deploySlotMachine();
}