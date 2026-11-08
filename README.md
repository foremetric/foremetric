# ForeMetric

**Infrastructure for the consented collection and monetization of behavioral data, delivering insights as a service to businesses and to users.**

People opt in to share behavioral signals from their phones and are credited for what they share; from token launch, they share in the revenue. Businesses buy insights, never the data: there is no raw-data export endpoint, by construction.

Website: [foremetric.ai](https://foremetric.ai) | Contact: info@foremetric.ai | [X](https://x.com/foremetric)

Closed alpha waitlist: https://luma.com/bxt0dn3t

> **Status, November 2026:** pre-revenue, no users yet, no outside funding, and nobody has paid yet. The Telegram Mini App is in development. Much of what follows is design; the text says which phase each item belongs to.

## What ForeMetric is

One infrastructure, three sides:

- **People** opt in, choose what to share, and are credited for the signals they share; from token launch, they share in the revenue. In Phase 2 they also receive insights about their own patterns.
- **Businesses** buy answers to their questions as a service: cohort size, activity rhythm, timing, transitions between categories, and in Phase 2 predictive metrics. They never receive raw data or individual profiles.
- **AI teams** come last, in Phase 3, through federated learning, without transferring data.

What it is not: a data marketplace (there is no export endpoint) and not a token-emission scheme (the token has no mint function, and the referral is one level, 10%).

## Where we start

The narrowest wedge. Phase 1 starts with a Telegram Mini App as an onboarding funnel (distribution, consent, a TON wallet, one-level referrals) and tests, cheaply, whether people opt in, whether they come back, and whether a business pays. The first paid pilot is a $1-5K cohort-engagement report for consumer-fintech teams that buy traffic inside Telegram: an experiment testing willingness to pay, not an operating business model.

## Phases

| | Phase 1 (now) | Phase 2 (designed, not started) | Phase 3 (designed, no date) |
|---|---|---|---|
| Scope | Telegram Mini App as an onboarding and referral funnel: distribution, TON wallet, per-category consent, one-level referrals, IOU balance. Two signal categories only: Mini App session events and, optionally, DNS categories set up manually by the user | Native app with more signals collected on the device; attested natural-language queries for businesses; insights for users; token launch | Federated learning for AI teams; TON Storage as the only storage layer |
| Trust model | Disclosed trusted operator: we hold the encryption key (AWS KMS, with an audit trail of every access) and can in principle read the data | Hardware-attested computing, differential privacy, a hard minimum of 50 users per group | Decentralized attestation |
| Reports | Made by the team from PostgreSQL aggregations; the buyer receives an aggregate, never raw records or individual profiles | Attested queries | Same as Phase 2, with attestation verified by a quorum rather than a vendor |

Phases advance on metrics, not on dates. The Phase 1 gate includes a closed alpha that measures what brings people back, a first paid pilot, and a secured runway. If a gate is not passed, the phase continues.

## Status

- **Live:** a public prototype at foremetric.ai (simulated data, marked as such) and an Identity Vault contract on TON Testnet.
- **In development:** the Telegram Mini App, the Rust backend with a PostgreSQL IOU ledger that it is being connected to, and the DoH/DoT DNS server.
- **Designed, not built:** native app, confidential computing, revenue splitter, token launch, Signal Passport, Oracle, Missions, federated learning.

## Token ($HSIG)

A specification only: no token contract or splitter is deployed, and no income figure is promised. The design:

- Fixed supply of 1,000,000,000 and no mint function.
- 80% of gross B2B receipts flows back to contributors, 10% goes to the contributor's referrer (one level only) and 10% to the treasury. With no referrer, the treasury receives 20%. The split runs through an immutable splitter contract on TON.
- Before launch, balances are IOU entries in a ledger, converted 1:1 at launch. Launch coincides with Phase 2 and has no committed date.
- A 0.1% burn applies to peer-to-peer transfers; splitter distributions are exempt.

There is no token sale, presale or giveaway.

## What this repository is

The public front page of ForeMetric. Development happens in private repositories. Earlier public experiments, including a Jetton prototype with an admin-controlled mint operation (`OP_MINT`), are superseded by the current design, which has no mint function. They were never audited. Do not deploy or use them. No token contract is deployed.

## License

Code in this repository is released under the MIT License (see LICENSE).

*Nothing here is financial advice or an offer of securities or tokens.*
