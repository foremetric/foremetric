# Security Policy

## Supported Components

ForeMetric is in **pre-launch development**. No token contract or revenue splitter is deployed. The only deployed contract is the Identity Vault on TON Testnet, and the public prototype runs on simulated data.

| Component | Status | Reports accepted |
|---|---|---|
| Website and public prototype (foremetric.ai) | Live, simulated data | ✅ |
| Identity Vault contract (TON Testnet) | Live on testnet | ✅ |
| Telegram Mini App and its API | In development | ✅ once publicly released |
| Token contract and revenue splitter | Specification only, not deployed | Design feedback only |

This repository is the public front page of the project. Earlier public experiments published here, including a Jetton prototype with an admin-controlled mint operation, are superseded by the current design, were never audited and must not be deployed or used.

---

## Reporting a Vulnerability

We take security seriously and appreciate responsible disclosure.

### How to Report

**Email:** info@foremetric.ai  
**Subject line:** `Security Report - [Brief description]`

Please do not open a public issue or pull request for a vulnerability.

### What to Include

Please provide as much information as possible:

- Type of vulnerability (smart contract, web application, cryptographic, etc.)
- Affected component and, where relevant, its address, URL or version
- Steps to reproduce the issue
- Expected vs. actual behavior
- Proof of concept (if applicable)
- Impact assessment
- Suggested fix (optional but helpful)

### Response Time

We aim to acknowledge receipt of security reports within **72 hours**.

After the initial reply, we will keep you informed about the status of your report, including:

- Whether we confirm the issue
- The expected timeline for a fix
- When the fix is released

---

## Responsible Disclosure Policy

We ask that you:

✅ **DO:**
- Give us reasonable time to investigate and fix the issue before public disclosure
- Communicate clearly and respectfully
- Make a good faith effort to avoid privacy violations, data destruction and service interruption

❌ **DO NOT:**
- Exploit the vulnerability beyond what is necessary to demonstrate it
- Access data or systems you are not authorized to access
- Publicly disclose the vulnerability before we have had a chance to address it
- Demand compensation or threaten disclosure

---

## No Bounty Program

**ForeMetric does not currently offer bug bounties, token rewards or financial compensation for security reports.**

ForeMetric is a pre-launch project, and we do not pay for reports at this stage. We do appreciate the time security researchers spend on it.

What we **can** offer:

- Prompt, serious attention to your report
- Public acknowledgment (if you wish) after the issue is resolved
- A written confirmation that you reported the issue and that it was resolved, if you need one for your portfolio

**Warning:** If someone offers you "$HSIG tokens" or "ForeMetric tokens" in exchange for security work, it is **not** from us. No token is deployed.

---

## Scope

### In Scope

- Web application security issues at foremetric.ai (the website and the public prototype)
- Vulnerabilities in the Identity Vault contract on TON Testnet
- The Telegram Mini App and its API, once publicly released
- Cryptographic design and implementation flaws
- Design flaws in our published specification, including the token and splitter design, which is not deployed
- Documentation errors that could lead to security issues
- Exposed credentials: if you find an API key, private key or password in this repository or its history, report it privately and do not use it

### Out of Scope

- Social engineering attacks
- Physical security attacks
- Denial of service attacks
- Vulnerabilities in third-party software and services (Telegram, TON, cloud providers, GitHub) unless they directly impact ForeMetric
- Theoretical implementation vulnerabilities without a proof of concept
- Automated scanner output without a proof of concept
- The early experiments published in this repository (superseded, never audited, not in use)
- Systems that are not listed above, including our private repositories and infrastructure. If you are unsure, ask before testing.

---

## Our Commitment to You

When you report a security issue to us, we commit to:

1. **Responding promptly**: within 72 hours
2. **Taking your report seriously**: we will investigate every credible report
3. **Working with you**: we will keep you informed of our progress
4. **Giving credit**: if you want public acknowledgment, we will provide it

---

## Contact

**Email:** info@foremetric.ai

If you need an encrypted channel, say so in your first email.

Thank you for helping make ForeMetric secure.
