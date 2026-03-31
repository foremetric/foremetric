# Security Policy

ForeMetric takes security extremely seriously. We handle sensitive behavioral data, cryptographic primitives, and smart contracts on TON.

### Supported Versions

Only the latest main branch and released tags are supported.

### Reporting a Vulnerability

**Please do not report security issues publicly.**

We use a coordinated disclosure process:

1. Send a detailed report to **security@foremetric.ai**
2. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Any PoC (if safe)

3. We aim to acknowledge receipt within **48 hours** and provide a fix timeline within **5 business days**.

### PGP Key (optional but recommended)

We accept encrypted reports. Our security team PGP key is available upon request.

### Bounty for Security Issues

Serious vulnerabilities may qualify for a security bounty paid in $FORE (amount depends on severity).

| Severity       | Example                          | Bounty range      |
|----------------|----------------------------------|-------------------|
| Critical       | Remote code execution, TEE break | 150,000+ $FORE   |
| High           | Smart contract exploit, nullifier bypass | 75,000–120,000 $FORE |
| Medium         | Privacy leak, DoS                | 30,000–60,000 $FORE |

### Scope

- Smart contracts (Jetton 2.0, Signal Passport nullifier, etc.)
- TEE implementation and nullifier mechanism
- Proof-of-Behavior algorithm
- On-device and server-side code handling behavioral data

Out of scope: social engineering, spam, rate limiting, etc.

### Thank You

Security researchers and responsible disclosure help keep ForeMetric safe for millions of users. We deeply appreciate your efforts.

ForeMetric Security Team  
March 2026
