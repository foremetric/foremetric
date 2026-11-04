```markdown
# ForeMetric — Human Signal Intelligence on TON

**Users opt in and are credited for their behavioral signals from day one.
Businesses buy ready-made predictive insights — aggregate answers to specific
business questions. No raw data, no profiles, no export.**

[Website](https://foremetric.ai) · [Whitepaper EN](https://foremetric.ai/whitepaper_en.pdf) · [Whitepaper RU](https://foremetric.ai/whitepaper_ru.pdf) · [X / Twitter](https://x.com/foremetric)

## The problem

AI models degrade when trained on synthetic data — verified human signal is
AI's scarcest asset. Meanwhile, a trillion-dollar advertising economy runs on
behavioral data, and the people who generate it are not part of the deal: they
are harvested without consent and paid nothing.

ForeMetric closes both gaps on one infrastructure.

## The model: Insights-as-a-Service

Today, businesses that need answers about how people behave buy raw behavioral
datasets and hire analysts to find the patterns themselves. ForeMetric is
designed to flip this model: users opt in and are credited for their behavioral
signals from day one, while businesses buy ready-made predictive insights —
aggregate answers to specific business questions, computed over anonymized
behavioral vectors. No raw-data export endpoint exists by design.

Two circuits run on the same infrastructure:

- **User circuit — behavioral data collection with monetization for the people
  who generate it.** From day one, users are credited for their activity.
  From token launch, 80% of every B2B payment returns to signal owners through
  an immutable on-chain splitter. Every user grows a one-level referral network
  underneath them and earns 10% from invitees, executed by smart contract.
- **Business circuit — insights as a service, not data sales.** A business
  brings a question and receives a finished aggregate answer. Raw vectors never
  leave the secure environment, answers are computed for groups of 50+ people,
  and no dataset export exists. We take the pattern-finding on ourselves; the
  buyer gets the answer, not a dataset.

## What runs today is deliberately smaller than the model

- **Live:** public prototype at foremetric.ai (simulated data, marked as such
  everywhere), the Identity Vault contract on TON Testnet, and a Rust/Axum
  backend with a PostgreSQL IOU ledger being connected to the prototype.
- **Next gates, not promises:** a closed alpha measuring what brings people
  back, and a paid pilot — a $1–5K cohort engagement report for a first batch
  of 2–3 clients (first target vertical: consumer fintech) — testing whether
  businesses will pay. These are experiments, not an operating business model.
- **Designed, not built:** the $HSIG token and revenue splitter,
  hardware-attested processing (AMD SEV-SNP + COCOON TDX enclaves), on-device
  vectorization in the native app, Signal Passport, Missions, federated
  learning for AI labs.

## Phases

Phases are growth gates, not a roadmap on a calendar.

| | Phase 1 — now | Phase 2 — designed | Phase 3 — vision |
|---|---|---|---|
| Focus | A Telegram Mini App as a viral onboarding funnel: distribution, TON wallet, per-signal consent, one-level referral network | The model itself: native app, on-device processing, TEE enclaves, the B2B Terminal (question in plain language → attested aggregate answer), token launch | Federated learning on verified human behavior for AI labs; enterprise tasks; C2C Signal Passport |
| Trust model | Disclosed trusted-operator custody — we hold the keys and say so openly | Hardware-attested computing: not even the node operator can read enclave memory | Decentralized attestation |
| Settlement | IOU credits in a ledger; referral accruals | Immutable 80/10/10 revenue splitter at mainnet; IOU converted 1:1 | Full protocol economics |

Phases advance on gates — what brings people back, a first paid pilot, secured
runway — not on dates. No launch dates are committed.

## $HSIG token — a specification, not a deployed contract

- Jetton on TON. Fixed supply of 1,000,000,000. The contract design has no
  mint function.
- Each B2B payment is designed to split 80% to contributors, 10% to the
  single-level referrer and 10% to the treasury (80/20 when there is no
  referrer), hardcoded in immutable bytecode at mainnet.
- Payouts are backed by real B2B revenue only — no emission from air.
- Phase-1 balances are IOU entries in a ledger, converted 1:1 at token launch.
  No committed launch date.

There is no token sale, presale or giveaway.

## What this repository is

An archive of early protocol experiments: a Jetton prototype in Tolk, with
tests and wrappers, kept for transparency. It is not the product, it has not
been audited, and it does not describe the current design — the specification
above supersedes it. The contracts here contain operations the current design
rejected (e.g. `OP_MINT`); do not deploy or use them.

## Principles

- Consent first: users choose what is shared, per signal.
- Answers, not datasets: no raw-data export endpoint exists by construction.
- No unbacked emission: every payout is backed by real revenue.
- Disclosed trust model: Phase 1 is a named trusted operator; hardware
  attestation is Phase 2.

## Contact

[foremetric.ai](https://foremetric.ai) · info@foremetric.ai · [X / Twitter](https://x.com/foremetric)

## License

Code in this repository is released under the MIT License (see LICENSE).

*Nothing here is financial advice or an offer of securities or tokens.*
```
