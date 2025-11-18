// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*//////////////////////////////////////////////////////////////////////////
                                MINI BANK
    - Single-asset ETH bank
    - Tracks per-user balances
    - Users can deposit and withdraw
    - Owner has minimal admin powers (toggle deposits)
    - Designed to be boring & predictable (auditor style)
//////////////////////////////////////////////////////////////////////////*/

/**
 * @dev Custom errors are cheaper than strings in require().
 * They also make debugging / analysis easier.
 */
error NotOwner();
error ReentrantCall();
error DepositsDisabled();
error ZeroAmount();
error ZeroAddress();
error InsufficientBalance();
error TransferFailed();

/**
 * @title SimpleOwner
 * @notice Minimal ownership pattern used for admin access.
 * @dev Abstract; meant to be inherited by concrete contracts.
 */
abstract contract SimpleOwner {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Internal initializer for ownership.
     *      Must be called exactly once from the constructor of the inheriting contract.
     */
    function _initOwner(address initialOwner) internal {
        if (initialOwner == address(0)) revert ZeroAddress();
        if (_owner != address(0)) revert NotOwner(); // already initialized
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @notice Returns the current owner.
    function owner() public view returns (address) {
        return _owner;
    }

    /// @dev Restricts a function to be callable only by the owner.
    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    /// @notice Transfers ownership to a new address.
    /// @dev No two-step transfer for simplicity; in production you might want a pendingOwner pattern.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /// @notice Renounces ownership permanently.
    /// @dev After this, onlyOwner functions become unusable.
    function renounceOwnership() external onlyOwner {
        address oldOwner = _owner;
        _owner = address(0);
        emit OwnershipTransferred(oldOwner, address(0));
    }
}

/**
 * @title ReentrancyGuard
 * @notice Standard "status flag" reentrancy guard.
 * @dev This is function-scoped protection; it does not try to be a global state machine.
 */
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        // Initialize to "not entered" so the first call passes.
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrantCall();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/**
 * @title MiniBank
 * @author (you)
 * @notice Minimal ETH bank intended as a reference-quality implementation.
 * @dev This contract is intentionally simple:
 *      - No interest
 *      - No fees
 *      - No ERC20 support
 *
 * SECURITY MODEL
 * --------------
 * 1. Funds are held directly by this contract in ETH (no external vault).
 * 2. Each user has a balance tracked in `_balances[user]`.
 * 3. Users can only move their own balance.
 * 4. All external calls that can send ETH use:
 *      - nonReentrant modifier
 *      - checks-effects-interactions ordering
 *
 * INVARIANTS (high-level, not enforced on-chain):
 * -----------------------------------------------
 *  - For any user `u`: _balances[u] >= 0 (always true with uint256).
 *  - Sum(_balances[u] for all u) <= address(this).balance
 *      (can be strictly less if the owner sends ETH directly to the contract
 *       and doesn't credit balances; we do not try to enforce equality).
 */
contract MiniBank is SimpleOwner, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Per-user ETH balances (in wei).
    mapping(address => uint256) private _balances;

    /// @dev Whether new deposits are currently allowed.
    /// Deposits can be disabled, but withdrawals remain available so users can always exit.
    bool private _depositsEnabled;

    /*//////////////////////////////////////////////////////////////////////////
                                     EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user deposits ETH.
    event Deposit(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws ETH.
    event Withdraw(address indexed user, uint256 amount);

    /// @notice Emitted when deposit enable status changes.
    event DepositsEnabledChanged(bool enabled);

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @param initialOwner The address that will be granted admin rights.
    constructor(address initialOwner) {
        _initOwner(initialOwner);
        _depositsEnabled = true;
    }

    /*//////////////////////////////////////////////////////////////////////////
                             EXTERNAL USER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit ETH into the bank.
     * @dev
     * - Fails if deposits are currently disabled.
     * - Fails if msg.value == 0 (no dust calls).
     * - Emits a Deposit event on success.
     */
    function deposit() external payable {
        if (!_depositsEnabled) revert DepositsDisabled();
        if (msg.value == 0) revert ZeroAmount();

        _deposit(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw ETH from your balance.
     * @dev
     * - nonReentrant due to external call to msg.sender.
     * - Uses checks-effects-interactions.
     * @param amount Amount in wei to withdraw.
     */
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 userBalance = _balances[msg.sender];
        if (userBalance < amount) revert InsufficientBalance();

        // EFFECTS: update state before external call.
        unchecked {
            // safe because we already required userBalance >= amount
            _balances[msg.sender] = userBalance - amount;
        }

        // INTERACTIONS: external call last.
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @notice Fallback entry point for plain ETH transfers.
     * @dev
     * An auditor would make this behavior explicit:
     *  - Either revert (force users to call deposit())
     *  - Or treat it as a deposit
     *
     * Here we choose to treat direct ETH sends as deposits to avoid "lost ETH" scenarios,
     * and to keep invariant "all ETH is either in user balances or considered surplus".
     */
    receive() external payable {
        if (!_depositsEnabled) revert DepositsDisabled();
        if (msg.value == 0) revert ZeroAmount();

        _deposit(msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////////////////
                              ADMIN / OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Enable or disable new deposits.
     * @dev
     * - Withdrawals are NOT affected.
     * - Design choice: users must always be able to withdraw.
     */
    function setDepositsEnabled(bool enabled) external onlyOwner {
        _depositsEnabled = enabled;
        emit DepositsEnabledChanged(enabled);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the ETH balance of a given user as recorded by the bank.
    function balanceOf(address user) external view returns (uint256) {
        return _balances[user];
    }

    /// @notice Returns whether new deposits are currently allowed.
    function depositsEnabled() external view returns (bool) {
        return _depositsEnabled;
    }

    /// @notice Returns the total ETH held by this contract.
    /// @dev This may be >= sum of user balances if someone sends ETH without going through deposit().
    function totalBankBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            INTERNAL HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal deposit function shared by deposit() and receive().
     *      Having a single code path reduces the chance of subtle differences.
     */
    function _deposit(address user, uint256 amount) internal {
        // NOTE: user and amount are trusted here because:
        // - user is always msg.sender in our entry points
        // - amount is always msg.value
        _balances[user] += amount;
        emit Deposit(user, amount);
    }
}
