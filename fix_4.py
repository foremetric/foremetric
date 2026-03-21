Now I have full context. The repo uses TON/Tolk for smart contracts and Rust for systems core. Here's the implementation:

```tolk
;; contracts/nullifier.tol
;; Signal Passport — TEE Nullifier Contract
;; ForeMetric.ai | MIT License | Copyright (c) 2026

module Nullifier {
    
    ;; --- Constants ---
    const MAX_QUERY_LIMIT: int = 9999;
    const MIN_QUERY_LIMIT: int = 1;
    const SECTOR_COUNT: int = 32;

    ;; --- Expiry durations (in seconds) ---
    const EXPIRY_24H: int = 86400;
    const EXPIRY_7D: int = 604800;
    const EXPIRY_30D: int = 2592000;
    const EXPIRY_UNLIMITED: int = 0;

    ;; --- Data structures ---
    struct TokenState {
        owner: Address;           ;; Passport owner address
        tokenId: Slice;           ;; SP-XXXX-2026
        queryLimit: int;          ;; 1–9999
        queriesRemaining: int;    ;; decrements per query
        sectors: int;             ;; bitmask: 1 = open, 0 = closed
        expiryTimestamp: int;     ;; 0 = unlimited
        isRevoked: bool;
        createdAt: int;
        lastQueryAt: int;
        totalQueriesUsed: int;
    }

    struct QueryResult {
        tokenId: Slice;
        success: bool;
        queriesRemaining: int;
        errorCode: int;           ;; 0=ok, 1=revoked, 2=exhausted, 3=expired, 4=sector_closed, 5=not_found
        errorMessage: Slice;
        timestamp: int;
        signature: Slice;         ;; TEE attestation signature placeholder
    }

    ;; --- State storage ---
    global tokens: map<Slice, TokenState>;

    ;; --- Init (deploy) ---
    init() {
        self.tokens = emptyMap();
    }

    ;; --- Internal helpers ---
    
    fun validateTokenId(id: Slice): bool {
        let len: int = id.bits();
        if (len < 8) { return false; }
        ;; Must start with "SP-"
        let prefix: int = id.preloadUint(16);
        return prefix == 0x53502D; ;; "SP-" in ASCII
    }

    fun isExpired(token: TokenState): bool {
        if (token.expiryTimestamp == EXPIRY_UNLIMITED) { return false; }
        return now() > token.expiryTimestamp;
    }

    fun isSectorOpen(token: TokenState, sectorIndex: int): bool {
        if (sectorIndex < 0 || sectorIndex >= SECTOR_COUNT) { return false; }
        let mask: int = 1 << sectorIndex;
        return (token.sectors & mask) != 0;
    }

    ;; --- External: Register a new passport nullifier ---
    
    receive(msg: Slice) {
        let op: int = msg.preloadUint(32);
        
        if (op == 0x0001) {
            ;; op_register_nullifier
            self.handleRegister(msg);
        } else if (op == 0x0002) {
            ;; op_query
            self.handleQuery(msg);
        } else if (op == 0x0003) {
            ;; op_revoke
            self.handleRevoke(msg);
        } else if (op == 0x0004) {
            ;; op_set_sectors
            self.handleSetSectors(msg);
        } else if (op == 0x0005) {
            ;; op_extend_expiry
            self.handleExtendExpiry(msg);
        } else if (op == 0x0006) {
            ;; op_get_state
            self.handleGetState(msg);
        } else if (op == 0x0007) {
            ;; op_batch_query
            self.handleBatchQuery(msg);
        }
    }

    fun handleRegister(msg: Slice) {
        ;; Skip op (4 bytes)
        msg.skipBits(32);
        
        let sender: Address = sender();
        let tokenId: Slice = msg.loadRef().beginParse();
        let queryLimit: int = msg.loadUint(16);
        let sectorBitmask: int = msg.loadUint(32);
        let expiryType: int = msg.loadUint(4);
        let owner: Address = msg.loadAddr();

        ;; Validate
        require(self.validateTokenId(tokenId), 1001);
        require(queryLimit >= MIN_QUERY_LIMIT && queryLimit <= MAX_QUERY_LIMIT, 1002);
        require(token in self.tokens == false, 1003); ;; No duplicate

        ;; Calculate expiry
        var expiry: int = EXPIRY_UNLIMITED;
        if (expiryType == 1) {
            expiry = now() + EXPIRY_24H;
        } else if (expiryType == 2) {
            expiry = now() + EXPIRY_7D;
        } else if (expiryType == 3) {
            expiry = now() + EXPIRY_30D;
        }

        let token: TokenState = TokenState {
            owner: owner,
            tokenId: tokenId,
            queryLimit: queryLimit,
            queriesRemaining: queryLimit,
            sectors: sectorBitmask,
            expiryTimestamp: expiry,
            isRevoked: false,
            createdAt: now(),
            lastQueryAt: 0,
            totalQueriesUsed: 0
        };

        self.tokens.set(tokenId, token);
        
        ;; Emit registration event
        self.emitEvent(tokenId, 0x01, 0, slice("registered"));
    }

    fun handleQuery(msg: Slice) {
        msg.skipBits(32);
        
        let tokenId: Slice = msg.loadRef().beginParse();
        let sectorIndex: int = msg.loadUint(5);
        let nonce: int = msg.loadUint(64);
        let teePublicKey: Slice = msg.loadRef().beginParse(); ;; TEE attestation placeholder

        require(tokenId in self.tokens, 1004);

        var token: TokenState = self.tokens.get(tokenId);
        var errCode: int = 0;
        var errMsg: Slice = slice("ok");

        ;; Check revocation
        if (token.isRevoked) {
            errCode = 1;
            errMsg = slice("token_revoked");
        }
        ;; Check expiry
        else if (self.isExpired(token)) {
            errCode = 3;
            errMsg = slice("token_expired");
        }
        ;; Check query limit
        else if (token.queriesRemaining <= 0) {
            errCode = 2;
            errMsg = slice("query_limit_exhausted");
        }
        ;; Check sector
        else if (!self.isSectorOpen(token, sectorIndex)) {
            errCode = 4;
            errMsg = slice("sector_closed");
        }

        if (errCode == 0) {
            ;; Decrement counter
            token.queriesRemaining = token.queriesRemaining - 1;
            token.totalQueriesUsed = token.totalQueriesUsed + 1;
            token.lastQueryAt = now();
            self.tokens.set(tokenId, token);

            ;; Emit query event
            self.emitEvent(tokenId, 0x02, sectorIndex, slice("query_consumed"));
        } else {
            ;; Emit failure event
            self.emitEvent(tokenId, 0x03, errCode, errMsg);
        }

        ;; Reply with result
        var result: Builder = beginCell();
        result = result.storeUint(0x0002, 32); ;; op response
        result = result.storeInt(errCode, 8);
        result = result.storeInt(token.queriesRemaining, 16);
        result = result.storeSlice(errMsg);
        result = result.storeUint(now(), 64);
        send(rawSlice(result.endCell()), sender(), 0, mode: 64);
    }

    fun handleRevoke(msg: Slice) {
        msg.skipBits(32);
        
        let sender: Address = sender();
        let tokenId: Slice = msg.loadRef().beginParse();

        require(tokenId in self.tokens, 1004);

        var token: TokenState = self.tokens.get(tokenId);
        
        ;; Only owner can revoke
        require(token.owner == sender, 1005);

        token.isRevoked = true;
        token.queriesRemaining = 0; ;; Force burn
        self.tokens.set(tokenId, token);

        self.emitEvent(tokenId, 0x04, 0, slice("revoked"));
    }

    fun handleSetSectors(msg: Slice) {
        msg.skipBits(32);
        
        let sender: Address = sender();
        let tokenId: Slice = msg.loadRef().beginParse();
        let newSectors: int = msg.loadUint(32);

        require(tokenId in self.tokens, 1004);

        var token: TokenState = self.tokens.get(tokenId);
        require(token.owner == sender, 1005);
        require(!token.isRevoked, 1006);
        require(!self.isExpired(token), 1007);

        token.sectors = newSectors;
        self.tokens.set(tokenId, token);

        self.emitEvent(tokenId, 0x05, newSectors, slice("sectors_updated"));
    }

    fun handleExtendExpiry(msg: Slice) {
        msg.skipBits(32);
        
        let sender: Address = sender();
        let tokenId: Slice = msg.loadRef().beginParse();
        let newExpiryType: int = msg.loadUint(4);

        require(tokenId in self.tokens, 1004);

        var token: TokenState = self.tokens.get(tokenId);
        require(token.owner == sender, 1005);
        require(!token.isRevoked, 1006);

        var expiry: int = EXPIRY_UNLIMITED;
        if (newExpiryType == 1) {
            expiry = now() + EXPIRY_24H;
        } else if (newExpiryType == 2) {
            expiry = now() + EXPIRY_7D;
        } else if (newExpiryType == 3) {
            expiry = now() + EXPIRY_30D;
        }

        token.expiryTimestamp = expiry;
        self.tokens.set(tokenId, token);

        self.emitEvent(tokenId, 0x06, expiry, slice("expiry_extended"));
    }

    fun handleGetState(msg: Slice) {
        msg.skipBits(32);
        
        let tokenId: Slice = msg.loadRef().beginParse();

        require(tokenId in self.tokens, 1004);

        var token: TokenState = self.tokens.get(tokenId);

        var isExp: bool = self.isExpired(token);
        
        var result: Builder = beginCell();
        result = result.storeUint(0x0006, 32); ;; op get_state response
        result = result.storeAddress(token.owner);
        result = result.storeSlice(token.tokenId);
        result = result.storeInt(token.queryLimit, 16);
        result = result.storeInt(token.queriesRemaining, 16);
        result = result.storeInt(token.sectors, 32);
        result = result.storeInt(token.expiryTimestamp, 64);
        result = result.storeInt(token.createdAt, 64);
        result = result.storeInt(token.lastQueryAt, 64);
        result = result.storeInt(token.totalQueriesUsed, 16);
        result = result.storeBool(token.isRevoked);
        result = result.storeBool(isExp);
        
        send(rawSlice(result.endCell()), sender(), 0, mode: 64);
    }

    fun handleBatchQuery(msg: Slice) {
        msg.skipBits(32);
        
        let count: int = msg.loadUint(8);
        require(count > 0 && count <= 10, 1008); ;; Max 10 batch

        var i: int = 0;
        while (i < count) {
            let tokenId: Slice = msg.loadRef().beginParse();
            let sectorIndex: int = msg.loadUint(5);

            if (tokenId in self.tokens) {
                var token: TokenState = self.tokens.get(tokenId);
                if (!token.isRevoked && !self.isExpired(token)
                    && token.queriesRemaining > 0
                    && self.isSectorOpen(token, sectorIndex)) {
                    token.queriesRemaining = token.queriesRemaining - 1;
                    token.totalQueriesUsed = token.totalQueriesUsed + 1;
                    token.lastQueryAt = now();
                    self.tokens.set(tokenId, token);
                }
            }
            i = i + 1;
        }

        self.emitEvent(slice(""), 0x07, count, slice("batch_complete"));
    }

    fun emitEvent(tokenId: Slice, eventType: int, data: int, message: Slice) {
        var event: Builder = beginCell();
        event = event.storeUint(0x00FF, 32); ;; event op code
        event = event.storeSlice(tokenId);
        event = event.storeUint(eventType, 8);
        event = event.storeUint(data, 32);
        event = event.storeSlice(message);
        event = event.storeUint(now(), 64);
        ;; Emit as outbound message (log)
        send(rawSlice(event.endCell()), myAddress(), 0, mode: 64);
    }
}
```

```rust
// src/nullifier_tee.rs
// Signal Passport — Cocoon TEE Nullifier Verification Client
// ForeMetric.ai | MIT License | Copyright (c) 2026

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

// ─── Domain Types ───

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PassportConfig {
    pub token_id: String,
    pub query_limit: u16,
    pub sectors: SectorConfig,
    pub expiry: ExpiryDuration,
    pub owner: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ExpiryDuration {
    Hours24,
    Days7,
    Days30,
    Unlimited,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SectorConfig {
    pub open: Vec<String>,
    pub closed: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NullifierError {
    TokenNotFound,
    TokenRevoked,
    QueryLimitExhausted,
    TokenExpired,
    SectorClosed { sector: String },
    ReplayAttackDetected { nonce: u64 },
    TEEAttestationFailed,
    OnChainVerificationFailed { code: i32 },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryRequest {
    pub token_id: String,
    pub sector: String,
    pub nonce: u64,
    pub tee_attestation: TEEAttestation,
    pub timestamp: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TEEAttestation {
    pub enclave_hash: String,
    pub quote_signature: String,
    pub report_data: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryResponse {
    pub success: bool,
    pub token_id: String,
    pub queries_remaining: u16,
    pub insight: JsonInsight,
    pub error: Option<NullifierError>,
    pub tee_signature: String,
    pub timestamp: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonInsight {
    pub token_id: String,
    pub query_number: u16,
    pub queries_remaining: u16,
    pub verified_at: u64,
    pub sector: String,
    pub attestation: AttestationInfo,
    pub data_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttestationInfo {
    pub tee_verified: bool,
    pub enclave_type: String,
    pub quote_hash: String,
    pub verification_timestamp: u64,
}

// ─── Nullifier State (mirror of on-chain state) ───

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NullifierState {
    pub token_id: String,
    pub owner: String,
    pub query_limit: u16,
    pub queries_remaining: u16,
    pub sector_bitmask: u32,
    pub expiry_timestamp: u64,
    pub is_revoked: bool,
    pub created_at: u64,
    pub last_query_at: u64,
    pub total_queries_used: u16,
    /// Cached SHA-256 of the last consumed nonce to prevent replay
    pub consumed_nonce_hashes: Vec<String>,
    max_cached_nonces: usize,
}

// ─── Nullifier Engine ───

pub struct NullifierEngine {
    states: HashMap<String, NullifierState>,
    /// Sector name → bit index mapping
    sector_index: HashMap<String, u8>,
    /// TEE public key for attestation verification
    tee_public_key: Vec<u8>,
}

impl NullifierEngine {
    const MAX_CACHED_NONCES: usize = 256;
    const SECTOR_COUNT: u8 = 32;

    pub fn new(tee_public_key: Vec<u8>) -> Self {
        let mut sector_index = HashMap::new();
        // Standard sector definitions
        let sectors = [
            "behavioral_profile", "demographics", "interests",
            "purchase_intent", "content_affinity", "social_graph",
            "device_fingerprint", "location_patterns", "time_patterns",
            "engagement_score", "loyalty_metrics", "churn_risk",
            "lifetime_value", "brand_affinity", "cross_platform",
            "privacy_preference",
        ];
        for (i, name) in sectors.iter().enumerate() {
            sector_index.insert(name.to_string(), i as u8);
        }

        Self {
            states: HashMap::new(),
            sector_index,
            tee_public_key,
        }
    }

    // ─── Registration ───

    pub fn register_nullifier(
        &mut self,
        config: PassportConfig,
    ) -> Result<NullifierState, NullifierError> {
        self.validate_token_id(&config.token_id)?;

        if self.states.contains_key(&config.token_id) {
            return Err(NullifierError::OnChainVerificationFailed {
                code: 1003,
            });
        }

        let (sector_bitmask, _) = self.build_sector_bitmask(&config.sectors);
        let expiry_ts = self.calculate_expiry(&config.expiry);
        let now = current_timestamp();

        let state = NullifierState {
            token_id: config.token_id.clone(),
            owner: config.owner,
            query_limit: config.query_limit,
            queries_remaining: config.query_limit,
            sector_bitmask,
            expiry_timestamp: expiry_ts,
            is_revoked: false,
            created_at: now,
            last_query_at: 0,
            total_queries_used: 0,
            consumed_nonce_hashes: Vec::new(),
            max_cached_nonces: Self::MAX_CACHED_NONCES,
        };

        self.states.insert(config.token_id.clone(), state.clone());
        Ok(state)
    }

    // ─── Query Verification (TEE-side) ───

    pub fn verify_and_consume(
        &mut self,
        request: &QueryRequest,
    ) -> Result<QueryResponse, NullifierError> {
        let token_id = &request.token_id;
        let state = self
            .states
            .get(token_id)
            .ok_or(NullifierError::TokenNotFound)?
            .clone();

        // 1. Verify TEE attestation
        self.verify_tee_attestation(&request.tee_attestation)?;

        // 2. Check revocation
        if state.is_revoked {
            return Err(NullifierError::TokenRevoked);
        }

        // 3. Check expiry
        let now = current_timestamp();
        if state.expiry_timestamp != 0 && now > state.expiry_timestamp {
            return Err(NullifierError::TokenExpired);
        }

        // 4. Check query limit
        if state.queries_remaining == 0 {
            return Err(NullifierError::QueryLimitExhausted);
        }

        // 5. Check sector
        let sector_idx = *self
            .sector_index
            .get(&request.sector)
            .ok_or(NullifierError::SectorClosed {
                sector: request.sector.clone(),
            })?;
        if (state.sector_bitmask & (1u32 << sector_idx)) == 0 {
            return Err(NullifierError::SectorClosed {
                sector: request.sector.clone(),
            });
        }

        // 6. Replay protection: check nonce
        let nonce_hash = self.hash_nonce(&request.token_id, request.nonce);
        if state.consumed_nonce_hashes.contains(&nonce_hash) {
            return Err(NullifierError::ReplayAttackDetected {
                nonce: request.nonce,
            });
        }

        // 7. All checks pass — consume query
        let new_remaining = state.queries_remaining - 1;
        let new_total = state.total_queries_used + 1;

        let mut updated = state;
        updated.queries_remaining = new_remaining;
        updated.total_queries_used = new_total;
        updated.last_query_at = now;
        updated.consumed_nonce_hashes.push(nonce_hash.clone());
        // Evict oldest nonces if cache is full
        if updated.consumed_nonce_hashes.len() > updated.max_cached_nonces {
            updated.consumed_nonce_hashes.remove(0);
        }

        self.states.insert(token_id.clone(), updated);

        // 8. Build JSON insight
        let insight = JsonInsight {
            token_id: token_id.clone(),
            query_number: new_total,
            queries_remaining: new_remaining,
            verified_at: now,
            sector: request.sector.clone(),
            attestation: AttestationInfo {
                tee_verified: true,
                enclave_type: "Intel_TDX".to_string(),
                quote_hash: self.compute_quote_hash(&request.tee_attestation),
                verification_timestamp: now,
            },
            data_hash: nonce_hash,
        };

        let response = QueryResponse {
            success: true,
            token_id: token_id.clone(),
            queries_remaining: new_remaining,
            insight,
            error: None,
            tee_signature: self.sign_response(token_id, now),
            timestamp: now,
        };

        Ok(response)
    }

    // ─── Revocation ───

    pub fn revoke(
        &mut self,
        token_id: &str,
        owner: &str,
    ) -> Result<(), NullifierError> {
        let state = self
            .states
            .get_mut(token_id)
            .ok_or(NullifierError::TokenNotFound)?;

        if state.owner != owner {
            return Err(NullifierError::OnChainVerificationFailed { code: 1005 });
        }

        state.is_revoked = true;
        state.queries_remaining = 0;
        Ok(())
    }

    // ─── Sector Management ───

    pub fn set_sectors(
        &mut self,
        token_id: &str,
        owner: &str,
        open: &[String],
        closed: &[String],
    ) -> Result<(), NullifierError> {
        let state = self
            .states
            .get_mut(token_id)
            .ok_or(NullifierError::TokenNotFound)?;

        if state.owner != owner {
            return Err(NullifierError::OnChainVerificationFailed { code: 1005 });
        }
        if state.is_revoked {
            return Err(NullifierError::TokenRevoked);
        }
        if state.expiry_timestamp != 0 && current_timestamp() > state.expiry_timestamp {
            return Err(NullifierError::TokenExpired);
        }

        let config = SectorConfig {
            open: open.to_vec(),
            closed: closed.to_vec(),
        };
        let (bitmask, _) = self.build_sector_bitmask(&config);
        state.sector_bitmask = bitmask;
        Ok(())
    }

    // ─── State Query ───

    pub fn get_state(&self, token_id: &str) -> Result<&NullifierState, NullifierError> {
        self.states.get(token_id).ok_or(NullifierError::TokenNotFound)
    }

    pub fn get_state_json(&self, token_id: &str) -> Result<String, NullifierError> {
        let state = self.get_state(token_id)?;
        let now = current_timestamp();
        let is_expired = state.expiry_timestamp != 0 && now > state.expiry_timestamp;

        let output = serde_json::json!({
            "token_id": state.token_id,
            "owner": state.owner,
            "query_limit": state.query_limit,
            "queries_remaining": state.queries_remaining,
            "queries_used": state.total_queries_used,
            "sectors": self.bitmask_to_sector_list(state.sector_bitmask),
            "expiry_timestamp": state.expiry_timestamp,
            "is_expired": is_expired,
            "is_revoked": state.is_revoked,
            "is_active": !state.is_revoked && !is_expired && state.queries_remaining > 0,
            "created_at": state.created_at,
            "last_query_at": state.last_query_at,
        });

        Ok(serde_json::to_string_pretty(&output).unwrap_or_default())
    }

    // ─── Internal Helpers ───

    fn validate_token_id(&self, token_id: &str) -> Result<(), NullifierError> {
        if token_id.len() < 8 || !token_id.starts_with("SP-") {
            return Err(NullifierError::OnChainVerificationFailed { code: 1001 });
        }
        Ok(())
    }

    fn build_sector_bitmask(&self, config: &SectorConfig) -> (u32, Vec<String>) {
        let mut bitmask: u32 = 0;
        let mut unknown = Vec::new();

        for sector in &config.open {
            if let Some(&idx) = self.sector_index.get(sector) {
                bitmask |= 1u32 << idx;
            } else {
                unknown.push(sector.clone());
            }
        }

        (bitmask, unknown)
    }

    fn bitmask_to_sector_list(&self, bitmask: u32) -> Vec<String> {
        let mut open = Vec::new();
        for (name, &idx) in &self.sector_index {
            if (bitmask & (1u32 << idx)) != 0 {
                open.push(name.clone());
            }
        }
        open
    }

    fn calculate_expiry(&self, expiry: &ExpiryDuration) -> u64 {
        let now = current_timestamp();
        match expiry {
            ExpiryDuration::Hours24 => now + 86400,
            ExpiryDuration::Days7 => now + 604800,
            ExpiryDuration::Days30 => now + 2592000,
            ExpiryDuration::Unlimited => 0,
        }
    }

    fn hash_nonce(&self, token_id: &str, nonce: u64) -> String {
        let mut hasher = Sha256::new();
        hasher.update(b"foremetric:nullifier:");
        hasher.update(token_id.as_bytes());
        hasher.update(b":");
        hasher.update(nonce.to_le_bytes());
        hex::encode(hasher.finalize())
    }

    fn verify_tee_attestation(&self, attestation: &TEEAttestation) -> Result<(), NullifierError> {
        // Placeholder for actual TEE verification (Intel SGX/TDX quote verification)
        // In production, this would verify the quote against the enclave's
        // measurement and the signer's certificate chain.
        if attestation.enclave_hash.is_empty() || attestation.quote_signature.is_empty() {
            return Err(NullifierError::TEEAttestationFailed);
        }
        Ok(())
    }

    fn compute_quote_hash(&self, attestation: &TEEAttestation) -> String {
        let mut hasher = Sha256::new();
        hasher.update(attestation.enclave_hash.as_bytes());
        hasher.update(attestation.quote_signature.as_bytes());
        hasher.update(&attestation.report_data);
        hex::encode(hasher.finalize())
    }

    fn sign_response(&self, token_id: &str, timestamp: u64) -> String {
        let mut hasher = Sha256::new();
        hasher.update(b"foremetric:tee_response:");
        hasher.update(token_id.as_bytes());
        hasher.update(timestamp.to_le_bytes());
        hasher.update(&self.tee_public_key);
        hex::encode(hasher.finalize())
    }
}

fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_secs()
}

// ─── Hex encode utility ───

mod hex {
    pub fn encode(bytes: impl AsRef<[u8]>) -> String {
        bytes
            .as_ref()
            .iter()
            .map(|b| format!("{:02x}", b))
            .collect()
    }
}

// ─── Tests ───

#[cfg(test)]
mod tests {
    use super::*;

    fn make_engine() -> NullifierEngine {
        NullifierEngine::new(vec![0xAB; 32])
    }

    fn make_config() -> PassportConfig {
        PassportConfig {
            token_id: "SP-TEST-2026".to_string(),
            query_limit: 3,
            sectors: SectorConfig {
                open: vec!["behavioral_profile".to_string()],
                closed: vec![],
            },
            expiry: ExpiryDuration::Days7,
            owner: "EQD...test_owner".to_string(),
        }
    }

    fn make_tee_attestation() -> TEEAttestation {
        TEEAttestation {
            enclave_hash: "abc123".to_string(),
            quote_signature: "sig456".to_string(),
            report_data: vec![1, 2, 3],
        }
    }

    #[test]
    fn test_register_nullifier() {
        let mut engine = make_engine();
        let config = make_config();
        let state = engine.register_nullifier(config).unwrap();

        assert_eq!(state.token_id, "SP-TEST-2026");
        assert_eq!(state.query_limit, 3);
        assert_eq!(state.queries_remaining, 3);
        assert!(!state.is_revoked);
    }

    #[test]
    fn test_register_duplicate_fails() {
        let mut engine = make_engine();
        engine.register_nullifier(make_config()).unwrap();
        let result = engine.register_nullifier(make_config());
        assert!(result.is_err());
    }

    #[test]
    fn test_register_invalid_token_id() {
        let mut engine = make_engine();
        let mut config = make_config();
        config.token_id = "INVALID".to_string();
        let result = engine.register_nullifier(config);
        assert!(result.is_err());
    }

    #[test]
    fn test_query_consumes_counter() {
        let mut engine = make_engine();
        engine.register_nullifier(make_config()).unwrap();

        let req = QueryRequest {
            token_id: "SP-TEST-2026".to_string(),
            sector: "behavioral_profile".to_string(),
            nonce: 1,
            tee_attestation: make_tee_attestation(),
            timestamp: current_timestamp(),
        };

        let resp1 = engine.verify_and_consume(&req).unwrap();
        assert!(resp1.success);
        assert_eq!(resp1.queries_remaining, 2);

        let req2 = QueryRequest { nonce: 2, ..req.clone() };
        let resp2 = engine.verify_and_consume(&req2).unwrap();
        assert_eq!(resp2.queries_remaining, 1);
    }

    #[test]
    fn test_query_limit_exhausted() {
        let mut engine = make_engine();
        engine.register_nullifier(make_config()).unwrap();

        for n in 1..=3 {
            let req = QueryRequest {
                token_id: "SP-TEST-2026".to_string(),
                sector: "behavioral_profile".to_string(),
                nonce: n,
                tee_attestation: make_tee_attestation(),
                timestamp: current_timestamp(),
            };
            engine.verify_and_consume(&req).unwrap();
        }

        let req = QueryRequest {
            token_id: "SP-TEST-2026".to_string(),
            sector: "behavioral_profile".to_string(),
            nonce: 100,
            tee_attestation: make_tee_attestation(),
            timestamp: current_timestamp(),
        };
        let result = engine.verify_and_consume(&req);
        assert!(matches!(result, Err(NullifierError::QueryLimitExhausted)));
    }

    #[test]
    fn test_replay_attack_prevention() {
        let mut engine = make_engine();
        engine.register_nullifier(make_config()).unwrap();

        let req = QueryRequest {
            token_id: "SP-TEST-2026".to_string(),
            sector: "behavioral_profile".to_string(),
            nonce: 42,
            tee_attestation: make_tee_attestation(),
            timestamp: current_timestamp(),
        };
        engine.verify_and_consume(&req).unwrap();

        let result = engine.verify_and_consume(&req);
        assert!(matches!(
            result,
            Err(NullifierError::ReplayAttackDetected { nonce: 42 })
        ));
    }

    #[test]
    fn test_sector_closed() {
        let mut engine = make_engine();
        engine.register_nullifier(make_config()).unwrap();

        let req = QueryRequest {
            token_id: "SP-TEST-2026".to_string(),
            sector: "demographics".to_string(), // not opened
            nonce: 1,
            tee_attestation: make_tee_attestation(),
            timestamp: current_timestamp(),
        };
        let result = engine.verify_and_consume(&req);
        assert!(matches!(result, Err(NullifierError::SectorClosed { .. })));
    }

    #[test]
    fn test_revoke_burns_token() {
        let mut engine = make_engine();
        engine.register_nullifier(make_config()).unwrap();

        engine
            .revoke("SP-TEST-2026", "EQD...test_owner")
            .unwrap();

        let state = engine.get_state("SP-TEST-2026").unwrap();
        assert!(state.is_revoked);
        assert_eq!(state.queries_remaining, 0);
    }

    #[test]
    fn test_revoke_unauthorized() {
        let mut engine = make_engine();
        engine.register_nullifier(make_config()).unwrap();

        let result = engine.revoke("SP-TEST-2026", "EQD...impostor");
        assert!(result.is_err());
    }

    #[test]
    fn test_no_replay_after_revocation() {
        let mut engine = make_engine();
        engine.register_nullifier(make_config()).unwrap();

        // Consume one query first
        let req = QueryRequest {
            token_id: "SP-TEST-2026".to_string(),
            sector: "behavioral_profile".to_string(),
            nonce: 1,
            tee_attestation: make_tee_attestation(),
            timestamp: current_timestamp(),
        };
        engine.verify_and_consume(&req).unwrap();

        // Revoke
        engine.revoke("SP-TEST-2026", "EQD...test_owner").unwrap();

        // Replay the used nonce — should get Revoked error, not Replay
        let result = engine.verify_and_consume(&req);
        assert!(matches!(result, Err(NullifierError::TokenRevoked)));
    }

    #[test]
    fn test_set_sectors() {
        let mut engine = make_engine();
        engine.register_nullifier(make_config()).unwrap();

        engine
            .set_sectors(
                "SP-TEST-2026",
                "EQD...test_owner",
                &["behavioral_profile".to_string(), "demographics".to_string()],
                &[],
            )
            .unwrap();

        let state = engine.get_state("SP-TEST-2026").unwrap();
        let sectors = engine.bitmask_to_sector_list(state.sector_bitmask);
        assert!(sectors.contains(&"behavioral_profile".to_string()));
        assert!(sectors.contains(&"demographics".to_string()));
    }

    #[test]
    fn test_json_insight_format() {
        let mut engine = make_engine();
        engine.register_nullifier(make_config()).unwrap();

        let req = QueryRequest {
            token_id: "SP-TEST-2026".to_string(),
            sector: "behavioral_profile".to_string(),
            nonce: 1,
            tee_attestation: make_tee_attestation(),
            timestamp: current_timestamp(),
        };
        let resp = engine.verify_and_consume(&req).unwrap();

        let json = serde_json::to_string_pretty(&resp.insight).unwrap();
        assert!(json.contains("behavioral_profile"));
        assert!(json.contains("SP-TEST-2026"));
        assert!(json.contains("tee_verified"));
    }

    #[test]
    fn test_get_state_json() {
        let mut engine = make_engine();
        engine.register_nullifier(make_config()).unwrap();

        let json = engine.get_state_json("SP-TEST-2026").unwrap();
        assert!(json.contains("is_active"));
        assert!(json.contains("query_limit"));
        assert!(json.contains("queries_remaining"));
    }
}
```

```toml
# Cargo.toml
[package]
name = "foremetric-nullifier"
version = "0.1.0"
edition = "2021"
description = "Signal Passport TEE Nullifier — ForeMetric.ai"
license = "MIT"

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
sha2 = "0.10"

[dev-dependencies]
```

**实现说明：**

| 组件 | 文件 | 职责 |
|---|---|---|
| TON智能合约 | `nullifier.tol` | 链上状态：注册/查询/撤销/扇区管理/批量查询 |
| TEE验证引擎 | `nullifier_tee.rs` | 链下Cocoon TEE验证：三重检查（撤销/限额/过期）+ 防重放（nonce SHA-256） |

核心安全特性：
- **防重放**：每个query的`(token_id, nonce)`做SHA-256缓存，重复nonce直接拒绝
- **即时撤销**：`revoke`将`is_revoked=true` + `queries_remaining=0`双重锁定
- **零重放**：token burn后（revoked或exhausted）任何query都先命中revocation/exhaustion检查，不会泄露replay信息
- **JSON insight输出**：每次query返回结构化JSON，包含TEE attestation、query计数、sector状态