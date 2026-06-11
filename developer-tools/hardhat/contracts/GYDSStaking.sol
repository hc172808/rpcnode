// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GYDSStaking
 * @notice Validator staking contract for GYDS Chain.
 *         Validators lock GYDS to earn the right to propose blocks.
 *         Minimum stake: 32,000 GYDS.
 *
 * Deploy on GYDS Chain (Chain ID 13370).
 */
contract GYDSStaking {
    uint256 public constant MIN_STAKE = 32_000 ether; // 32,000 GYDS

    address public owner;

    struct Validator {
        address addr;
        uint256 stake;
        bool    active;
        uint256 registeredAt;
        uint256 rewardDebt;
    }

    mapping(address => Validator) public validators;
    address[] public validatorList;

    uint256 public totalStaked;
    uint256 public rewardPool;

    event Registered(address indexed validator, uint256 stake);
    event Unstaked(address indexed validator, uint256 amount);
    event Slashed(address indexed validator, uint256 amount, string reason);
    event RewardDistributed(address indexed validator, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "GYDSStaking: not owner");
        _;
    }

    modifier onlyValidator() {
        require(validators[msg.sender].active, "GYDSStaking: not an active validator");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // ── Staking ───────────────────────────────────────────────
    function register() external payable {
        require(msg.value >= MIN_STAKE, "GYDSStaking: stake below minimum (32,000 GYDS)");
        require(!validators[msg.sender].active, "GYDSStaking: already registered");

        validators[msg.sender] = Validator({
            addr:         msg.sender,
            stake:        msg.value,
            active:       true,
            registeredAt: block.timestamp,
            rewardDebt:   0
        });
        validatorList.push(msg.sender);
        totalStaked += msg.value;

        emit Registered(msg.sender, msg.value);
    }

    function unstake() external onlyValidator {
        Validator storage v = validators[msg.sender];
        uint256 amount = v.stake;
        v.active = false;
        v.stake  = 0;
        totalStaked -= amount;
        payable(msg.sender).transfer(amount);
        emit Unstaked(msg.sender, amount);
    }

    // ── Rewards ───────────────────────────────────────────────
    function distributeRewards() external payable onlyOwner {
        require(validatorList.length > 0, "GYDSStaking: no validators");
        uint256 perValidator = msg.value / activeCount();
        for (uint256 i = 0; i < validatorList.length; i++) {
            Validator storage v = validators[validatorList[i]];
            if (v.active) {
                v.rewardDebt += perValidator;
            }
        }
        rewardPool += msg.value;
    }

    function claimReward() external onlyValidator {
        Validator storage v = validators[msg.sender];
        uint256 reward = v.rewardDebt;
        require(reward > 0, "GYDSStaking: no reward");
        v.rewardDebt = 0;
        rewardPool  -= reward;
        payable(msg.sender).transfer(reward);
        emit RewardDistributed(msg.sender, reward);
    }

    // ── Slashing (owner-only for now) ─────────────────────────
    function slash(address validator, uint256 amount, string calldata reason) external onlyOwner {
        Validator storage v = validators[validator];
        require(v.active, "GYDSStaking: not active");
        uint256 slashAmt = amount > v.stake ? v.stake : amount;
        v.stake    -= slashAmt;
        totalStaked -= slashAmt;
        if (v.stake < MIN_STAKE) {
            v.active = false;
        }
        emit Slashed(validator, slashAmt, reason);
    }

    // ── View helpers ──────────────────────────────────────────
    function isValidator(address addr) external view returns (bool) {
        return validators[addr].active;
    }

    function getValidators() external view returns (address[] memory) {
        return validatorList;
    }

    function activeCount() public view returns (uint256 count) {
        for (uint256 i = 0; i < validatorList.length; i++) {
            if (validators[validatorList[i]].active) count++;
        }
    }

    function pendingReward(address addr) external view returns (uint256) {
        return validators[addr].rewardDebt;
    }

    receive() external payable {}
}
