// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GYDSFaucet
 * @notice Testnet GYDS faucet — drips a small amount of GYDS to any address.
 *         The owner can top-up the faucet and adjust the drip amount / cooldown.
 *
 * Deploy on GYDS Chain (Chain ID 13370) then send GYDS to the contract address.
 */
contract GYDSFaucet {
    address public owner;
    uint256 public dripAmount   = 1 ether;   // 1 GYDS per request
    uint256 public cooldown     = 24 hours;   // 24h between drips per address

    mapping(address => uint256) public lastRequest;

    event Drip(address indexed to, uint256 amount);
    event Refill(address indexed from, uint256 amount);
    event DripAmountChanged(uint256 newAmount);
    event CooldownChanged(uint256 newCooldown);
    event Withdrawn(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "GYDSFaucet: not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // ── Public drip ───────────────────────────────────────────
    function drip(address payable to) external {
        require(address(this).balance >= dripAmount, "GYDSFaucet: empty");
        require(
            block.timestamp >= lastRequest[to] + cooldown,
            "GYDSFaucet: too soon"
        );
        lastRequest[to] = block.timestamp;
        to.transfer(dripAmount);
        emit Drip(to, dripAmount);
    }

    // Shorthand: drip to msg.sender
    function request() external {
        require(address(this).balance >= dripAmount, "GYDSFaucet: empty");
        require(
            block.timestamp >= lastRequest[msg.sender] + cooldown,
            "GYDSFaucet: too soon, cooldown not over"
        );
        lastRequest[msg.sender] = block.timestamp;
        payable(msg.sender).transfer(dripAmount);
        emit Drip(msg.sender, dripAmount);
    }

    // ── View helpers ──────────────────────────────────────────
    function balance() external view returns (uint256) {
        return address(this).balance;
    }

    function nextRequestAt(address addr) external view returns (uint256) {
        uint256 next = lastRequest[addr] + cooldown;
        return next > block.timestamp ? next : block.timestamp;
    }

    function canRequest(address addr) external view returns (bool) {
        return block.timestamp >= lastRequest[addr] + cooldown;
    }

    // ── Owner functions ───────────────────────────────────────
    function setDripAmount(uint256 amount) external onlyOwner {
        require(amount > 0, "GYDSFaucet: amount must be > 0");
        dripAmount = amount;
        emit DripAmountChanged(amount);
    }

    function setCooldown(uint256 seconds_) external onlyOwner {
        cooldown = seconds_;
        emit CooldownChanged(seconds_);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "GYDSFaucet: zero address");
        owner = newOwner;
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "GYDSFaucet: insufficient balance");
        payable(owner).transfer(amount);
        emit Withdrawn(owner, amount);
    }

    // Receive GYDS
    receive() external payable {
        emit Refill(msg.sender, msg.value);
    }
}
