# Vexqode (VQI)

Vexqode is a fixed-supply ERC-20. Its constructor mints **1,000,000,000 VQI**
with **18 decimals** to `msg.sender`, the immediate deployer. The supply in
smallest units is **1000000000000000000000000000** (`10^27`).

## Contract and assumptions

- Deployable artifact: `src/Vexqode.sol:Vexqode`.
- Constructor arguments: none; constructor value: zero.
- Name: `Vexqode`; symbol: `VQI`; decimals: `18`.
- Standard transfers and approvals use the vendored OpenZeppelin Contracts
  v5.0.2 ERC-20 implementation. Successful operations return `true`; failures
  revert with ERC-20 custom errors. Transfers deliver the exact requested amount.
- The requested token is interpreted as a plain ERC-20: no transfer fees,
  rebasing, burn interface, later minting, owner, pause, blacklist, upgrade,
  permit, or privileged balance movement.
- Zero-value transfers between valid addresses and self-transfers are supported.
  Transfers to the zero address and approvals to a zero spender revert.
- Finite allowances decrease on `transferFrom`; an allowance of `uint256.max`
  stays unchanged. `approve` replaces the existing allowance. Explicit approvals
  emit `Approval`; transfers, including constructor minting, emit `Transfer`.
  This implementation does not emit `Approval` when spending an allowance.

## Build and check

Install Foundry and make Solidity **0.8.26** available in its compiler cache.
All Solidity dependencies are vendored as ordinary files under `lib/`; no
dependency download or install step is needed. The compiler itself is a
toolchain prerequisite and is not included in the repository.

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimizer enabled
with 200 runs, and `bytecode_hash = "none"`. FFI and filesystem cheatcode
permissions are disabled. Dependency versions, upstream archives, checksums,
and license locations are in [DEPENDENCIES.md](DEPENDENCIES.md).

Tests use local fixtures only, with no RPC, secrets, environment-variable access,
filesystem access, or order dependencies. The suite covers metadata and supply,
constructor events, CREATE2 factory ownership of the initial supply, exact
transfers, approvals and revocation, allowance spending, failure rollback, zero
addresses, zero amounts, self-transfers, insufficient funds/allowances, and
rejection of minting and administrative calls. Fuzz tests run 512 cases each.
The stateful invariant runs 128 sequences of up to 64 calls across four holders,
checking supply and balance conservation after transfers, approvals, and
delegated transfers.

The launch-flow test models distributor, pool, and trader token movements.
Actual Uniswap pool initialization, liquidity seeding, and swaps belong to the
separate protected launch harness; this repository does not reproduce that
harness or its chain configuration.

## Deployment parameters

Deploy `Vexqode` directly on a chain compatible with the configured Cancun EVM
target. There is no initializer or post-deployment configuration. Deployment
requires no owner address, external contract, oracle, router, or other supplied
address. No launch economics or manifest is invented by this token project.

The **immediate constructor caller receives the entire supply**. A direct
deployment credits the deploying account. A deployment through a factory
(including CREATE2) credits the factory, not the transaction sender or origin.
The factory must be able to distribute its balance. Token creation code is the
compiled creation bytecode with no appended constructor arguments:

```sh
forge inspect src/Vexqode.sol:Vexqode bytecode
```

For the IdentityMD launch, the external factory is responsible for forwarding
the swarm allocation, seeding the pool, and distributing the remainder. Those
are ordinary exact-amount transfers; Vexqode requires no exemptions or launch
addresses. Deploy the concrete artifact, without a proxy or an unreviewed wrapper.
This project contains no wallet configuration or transaction-broadcast script.

## After launch

No settings or administrative maintenance are required. The launch operator is
responsible for securing the deploying account or factory, verifying the source
and compiler settings, checking the token metadata and initial mint event, and
executing the intended distribution. Check the full initial balance before any
distribution, or use the constructor `Transfer` event if the factory distributes
within the same transaction.

Holders control transfers and allowances. Approve only trusted spenders and
prefer the amount needed. When replacing an existing nonzero allowance, first
revoke it and confirm that transaction to mitigate the standard ERC-20 allowance
replacement race. Unlimited allowances remain usable until revoked. There is no
administrator who can recover lost keys, reverse transfers, or recover tokens
sent to the token contract or another contract unable to transfer them. Ordinary
native-currency sends revert; forcibly delivered native currency has no recovery
function.

## Security review scope

The implementation adds only constructor minting to the vendored ERC-20; it
does not override transfer or allowance logic. Its runtime performs no external
calls or receiver callbacks, and exposes no supply-changing or privileged entry
points. Local review checked exact base-unit supply, constructor caller semantics,
transfer conservation, allowance authorization and rollback, and absence of
upgrade, arbitrary-call, or destruction mechanisms. A runtime opcode regression
test checks for `DELEGATECALL`, `CALLCODE`, and `SELFDESTRUCT`.

Local validation uses Foundry unit, fuzz, and invariant tests. Slither and Mythril
were not run. This review and these tests are not an independent security audit;
the release operator remains responsible for separate adversarial review and
validation of the complete launch integration before release.
