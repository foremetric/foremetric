# ForeMetric

**Cohort analytics from consented behavioral data.**

ForeMetric lets consumer-fintech teams buy cohort-level reports on how Telegram users behave, from users who explicitly opt in and share in the revenue. Buyers receive aggregates, never raw data or individual profiles, and there is no export function.

Website: [foremetric.ai](https://foremetric.ai) | Contact: info@foremetric.ai

> **Status, November 2026:** pre-revenue, no users yet, no outside funding, and nobody has paid for a report. The Telegram Mini App is in development.

## What we are building

Companies that sell to consumers pay for knowledge of how real people behave, and the people who generate that behavior are not part of the deal. ForeMetric is built around consent and a revenue share, and it sells answers, not data.

The first product is deliberately small: a $1-5K cohort-engagement report for consumer-fintech acquisition teams that buy traffic inside Telegram. A report covers cohort size, activity rhythm, timing, and transitions between categories.

## Phases

| | Phase 1 (now) | Phase 2 (designed, not started) | Phase 3 (designed, no date) |
|---|---|---|---|
| Purpose | A cheap test: do people consent, do they come back, does a business pay | Native app, on-device processing, hardware-attested computing, differential privacy, a hard minimum of 50 users per group, token launch | Federated learning for AI teams, TON Storage, decentralized attestation |
| Signals | Two only: Mini App session events and optional DNS category data | More signals, collected on the device | |
| Trust model | Disclosed trusted operator: we hold the encryption key (AWS KMS, with an audit trail) and can technically read the data | Hardware attestation | Decentralized attestation |
| Reports | Made by the team from PostgreSQL aggregations | Attested queries | |

Phases advance on metrics, not on dates. The Phase 1 gate includes Day-7 retention of at least 20% in a closed alpha of up to 500 invited users, a first paid pilot, and a secured runway. If a gate is not passed, the phase continues.

## Status

- **Live:** a public prototype at foremetric.ai (simulated data, marked as such), a deployed Rust backend with a PostgreSQL ledger, and an Identity Vault contract on TON Testnet.
- **In development:** the Telegram Mini App and the DoH/DoT DNS server.
- **Designed, not built:** native app, confidential computing, revenue splitter, token launch, Signal Passport, Oracle, Missions, federated learning.

## Token ($HSIG)

A specification only: no token contract or splitter is deployed, and no income figure is promised. The design:

- Fixed supply of 1,000,000,000 and no mint function.
- 80% of gross B2B receipts flows back to contributors, 10% goes to a single-level referrer and 10% to the treasury (80/20 when there is no referrer), through an immutable splitter contract on TON.
- Before launch, balances are IOU entries in a ledger, converted 1:1 at launch. Launch coincides with Phase 2 and has no committed date.

There is no token sale, presale or giveaway.

## What this repository is

An archive of early experiments: a Jetton prototype in Tolk, with tests and wrappers. It is kept for transparency. It is not the product, it has not been audited, and it does not describe the current design; the specification above supersedes it. Do not deploy or use the contracts in this repository.

## Principles

- Consent first: users choose what to share.
- Answers, not data: there is no raw-data export endpoint, by construction.
- No unbacked emission: payouts are backed by real B2B revenue.
- Disclosed trust model: Phase 1 is a trusted operator, and hardware-attested privacy is Phase 2.

## License

Code in this repository is released under the MIT License (see LICENSE).

*Nothing here is financial advice or an offer of securities or tokens.*
