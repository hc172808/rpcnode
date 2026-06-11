const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const network    = await hre.ethers.provider.getNetwork();
  const balance    = await hre.ethers.provider.getBalance(deployer.address);

  console.log("╔══════════════════════════════════════════════════╗");
  console.log("║         GYDS Chain Contract Deployment            ║");
  console.log("╚══════════════════════════════════════════════════╝");
  console.log(`  Network   : ${network.name} (Chain ID ${network.chainId})`);
  console.log(`  Deployer  : ${deployer.address}`);
  console.log(`  Balance   : ${hre.ethers.formatEther(balance)} GYDS`);
  console.log("");

  if (network.chainId !== 13370n && network.chainId !== 31337n) {
    console.warn("⚠️  WARNING: Not connected to GYDS Chain (13370) or local hardhat.");
  }

  // ── Deploy GYDSFaucet ─────────────────────────────────────
  console.log("Deploying GYDSFaucet…");
  const Faucet = await hre.ethers.getContractFactory("GYDSFaucet");
  const faucet = await Faucet.deploy();
  await faucet.waitForDeployment();
  const faucetAddr = await faucet.getAddress();
  console.log(`  ✓ GYDSFaucet deployed → ${faucetAddr}`);

  // Fund faucet with 100 GYDS
  if (balance > hre.ethers.parseEther("100")) {
    const tx = await deployer.sendTransaction({
      to:    faucetAddr,
      value: hre.ethers.parseEther("100"),
    });
    await tx.wait();
    console.log(`  ✓ Funded faucet with 100 GYDS`);
  } else {
    console.warn("  ⚠️  Skipped faucet funding (balance too low)");
  }

  // ── Deploy GYDSStaking ────────────────────────────────────
  console.log("\nDeploying GYDSStaking…");
  const Staking = await hre.ethers.getContractFactory("GYDSStaking");
  const staking = await Staking.deploy();
  await staking.waitForDeployment();
  const stakingAddr = await staking.getAddress();
  console.log(`  ✓ GYDSStaking deployed → ${stakingAddr}`);

  // ── Summary ───────────────────────────────────────────────
  console.log("");
  console.log("╔══════════════════════════════════════════════════╗");
  console.log("║                 Deployment Summary               ║");
  console.log("╚══════════════════════════════════════════════════╝");
  console.log(`  GYDSFaucet  : ${faucetAddr}`);
  console.log(`  GYDSStaking : ${stakingAddr}`);
  console.log("");
  console.log("  Save these addresses! Add to your frontend config.");
  console.log("  To interact: hardhat console --network gyds");
  console.log("");
  console.log("  Faucet usage:");
  console.log("    const faucet = await ethers.getContractAt('GYDSFaucet', '<addr>');");
  console.log("    await faucet.request();  // drips 1 GYDS to caller");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
