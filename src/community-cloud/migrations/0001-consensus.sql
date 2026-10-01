CREATE TABLE candidates (
 id TEXT PRIMARY KEY, identity TEXT NOT NULL, row_json TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','ready','reviewing','approved','rejected','blocked','stalled','withdrawn')),
 devices INTEGER NOT NULL DEFAULT 0, networks INTEGER NOT NULL DEFAULT 0,
 created INTEGER NOT NULL, updated INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
 retry_at INTEGER NOT NULL DEFAULT 0, review_owner TEXT, lease_until INTEGER NOT NULL DEFAULT 0,
 review_json TEXT, reviewed_at INTEGER, published_version TEXT
);
CREATE INDEX candidates_identity ON candidates(identity);
CREATE INDEX candidates_queue ON candidates(state,retry_at,created);
CREATE UNIQUE INDEX one_approved_per_identity ON candidates(identity) WHERE state='approved';
CREATE TABLE supports (
 identity TEXT NOT NULL, device_hash TEXT NOT NULL, candidate_id TEXT NOT NULL REFERENCES candidates(id),
 network_hash TEXT NOT NULL, created INTEGER NOT NULL,
 PRIMARY KEY(identity,device_hash)
);
CREATE INDEX supports_candidate ON supports(candidate_id);
CREATE TABLE quotas(key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL, last_ticket TEXT NOT NULL);
CREATE TABLE leases(key TEXT PRIMARY KEY, owner TEXT NOT NULL, expires INTEGER NOT NULL);
CREATE TABLE publication (key TEXT PRIMARY KEY CHECK(key='official'), sequence INTEGER NOT NULL, last_at INTEGER NOT NULL DEFAULT 0,
 version TEXT NOT NULL DEFAULT '', digest TEXT NOT NULL DEFAULT '');
CREATE TABLE withdrawals(version TEXT PRIMARY KEY, reason TEXT NOT NULL, created INTEGER NOT NULL);
CREATE TABLE release_entries(candidate_id TEXT NOT NULL, version TEXT NOT NULL, PRIMARY KEY(candidate_id,version));
