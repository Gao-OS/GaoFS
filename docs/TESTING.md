# GaoFS v1 – Testing Architecture

Document Status: Frozen for v1

Goal: Convert GaoFS constraints into an automated, reproducible, cross-platform test system.

## 1. Testing Objectives

GaoFS v1 must prove:

- Structural safety: no metadata corruption after crashes.
- Deterministic recovery: replay produces the same mount state for the same durable history.
- Semantics correctness: rename atomicity; fsync/fdatasync durability.
- Cross-platform compatibility: same disk image mounts with same results on GaoOS + Linux (then BSD/macOS).
- Protocol correctness: IPC framing, ordering, error mapping.
- Regression resistance: golden images + seed replay.

Correctness is prioritized over performance. Performance benchmarks are tracked but not gatekeeping initially.

## 2. Test Pyramid

### 2.1 Core Unit Tests (fast)

Scope: `gaofs-core` modules only.

Must cover:

- Superblock parsing/validation (CRC, flags)
- Checkpoint parsing/selection
- BTree invariants (sorted keys, fanout, sibling links)
- Allocator bitmap invariants
- WAL record encode/decode + checksum
- Replay idempotency at record/txn level

Output: pass/fail + invariant diagnostics.

### 2.2 Property & Model Tests (medium)

Scope: core+server semantics with deterministic operation sequences.

Approach:

- Generate random op sequences with a fixed seed
- Apply to:
  - GaoFS (system under test)
  - Reference model (in-memory simplified FS model)
- After every op: check invariants; compare observable state.

Observable state definition (v1):

- `path → {type, mode, size, content hash (optional for small files)}`
- directory listing (set)
- stat fields (subset): mode, size, nlink

### 2.3 Crash Consistency Tests (critical)

Scope: WAL + metadata ordering + replay.

Approach:

- Run workload
- Inject crash at controlled failpoints (power loss / kill)
- Restart
- Mount + fsck + verify oracle state

Must simulate:

- crash after WAL append before flush
- crash after WAL flush before metadata write
- crash after metadata write before commit
- crash mid-checkpoint
- torn write in WAL / btree / bitmap
- reordered write visibility

### 2.4 Integration Tests (slow)

Scope: adapters + transport.

- GaoOS: `gaoos_vfs` + shm transport + server
- Linux: FUSE adapter + posix transport + server
- FreeBSD/macOS: FUSE-based later

Run:

- scripted functional tests
- concurrency tests
- protocol fuzz tests (framing/corruption)

### 2.5 Compatibility Tests (always)

Scope: golden images & backward compatibility.

- Build produces or consumes fixed disk images
- Verify invariants and expected directory tree
- Ensure unknown feature flags fail safely

## 3. Test Harness Components

All harness tools live under `tools/`:

```text
tools/
  fstorture/     # random op generator + oracle
  crashrun/      # crash injection runner
  imagegen/      # golden image generator
  check/         # uniform invariant checker wrapper (fsck + dumps)
  bench/         # benchmarks (non-gating initially)
```

### 3.1 Common Interfaces

#### Block Device Abstraction

All tests run on a pluggable `BlockDev`:

- `MemBlockDev` (in-memory)
- `FileBlockDev` (image file)
- `FaultBlockDev` (injection wrapper)

#### Fault Injection Interface

`FaultBlockDev` must support:

- fail read/write at op index N
- partial write (torn write) with byte cutoff
- reorder visibility (delayed commit queue)
- drop flush / ignore barrier

All fault behaviors must be:

- deterministic under seed
- reproducible by `(seed, step, fault_id)`

## 4. Invariants (Hard Requirements)

The following invariants are gating across most tests.

### 4.1 Superblock & Regions

- SB CRC valid (or backup SB used)
- region boundaries non-overlapping
- required incompat flags present (`FIXED_4K`, `CRC32C`, `WAL_V1`)

### 4.2 BTree

- keys sorted
- nkeys within bounds
- child pointers valid
- CRC valid for all reachable nodes
- leaf sibling chain acyclic and ordered

### 4.3 Allocator

- bitmap marks all referenced blocks allocated
- no block referenced by two owners (extent/meta)
- metadata blocks never allocated as data
- journal/checkpoint/sb blocks always allocated

### 4.4 Inode/Dirent

- root inode exists
- directory entries reference valid inodes
- nlink matches number of dir references (v1: conservative check acceptable)
- no extent overlap for a file
- extents in data region

## 5. Deterministic Oracle Definition

Testing uses two oracles:

### 5.1 Model Oracle (fast)

An in-memory model that supports v1 subset:

- files, directories, rename, unlink, truncate, read/write
- ignore atime
- enforce name length limits

Used for:

- random op tests
- small data verification

### 5.2 Host FS Oracle (optional / slow)

Mirror operations in a temp directory on host filesystem to compare:

- directory trees
- file sizes
- content hashes

Used selectively due to semantic differences (permissions, case sensitivity).

## 6. Crash Test Semantics (from CONSISTENCY.md)

Crash test assertions are operation-class based:

### 6.1 `write()` without `fsync`

After crash:

- data MAY be old or new
- size MAY be old or new

But must satisfy:

- filesystem mounts
- no corruption
- directory structure valid

### 6.2 `fdatasync()`

After crash:

- file data durable for synced ranges
- file size durable

But directory entry durability not required.

### 6.3 `fsync()`

After crash:

- file data durable
- size durable
- directory entry durable (if created/linked before fsync)

### 6.4 `rename()`

After crash:

- atomic: old exists XOR new exists (within same directory; cross-dir still atomic)
- never neither

The harness must encode these rules so tests remain decidable.

## 7. IPC Protocol Testing

### 7.1 Framing Tests

- header CRC validation
- payload_len bounds
- unknown opcode handling
- version negotiation behavior

### 7.2 Ordering Tests

Within a session:

- requests processed in order by default
- pipelined writes still preserve per-handle order semantics

### 7.3 Fuzz Tests

Generate malformed frames:

- truncated header
- wrong payload length
- CRC mismatch
- random opcode

Expected:

- server rejects request
- session remains safe or is closed cleanly
- no server crash

## 8. Test Suites

### 8.1 Functional Script Suite (per platform)

A portable script runner (or Zig test runner) that executes:

- mkdir/rmdir
- create/write/read
- truncate expand/shrink
- rename overwrite & non-overwrite
- unlink open-file (POSIX nuance: define v1 behavior clearly; if unsupported return ENOTSUP and test expects it)

### 8.2 Concurrency Suite

- parallel create/unlink in same dir
- parallel writes to different files
- rename storm (two names swapping)

Asserts:

- no deadlocks
- invariants hold

### 8.3 Large Directory Suite

- create 100k entries
- readdir paging correctness
- performance baseline recorded

### 8.4 Crash Matrix Suite (gating)

For each workload, crash at:

- after WAL append
- after WAL flush
- after metadata write
- before commit
- during checkpoint
- with torn write in WAL
- with torn write in btree
- with torn write in bitmap

Each must:

- mount successfully (or fail safely with “requires fsck”)
- fsck reports deterministically
- post-crash oracle assertions pass

## 9. Golden Images

`tools/imagegen` produces a set of canonical images:

- empty fs
- many small files
- large sparse file
- deep directories
- fragmented allocator
- journal dirty (requires replay)
- crash mid-rename
- bitmap corruption (fsck detects)

CI uses:

- `fsck.gaofs --readonly`
- `dump.gaofs --super --checkpoint --roots`
- mount + verify tree (where applicable)

## 10. CI Strategy

### PR (fast gate)

- core unit tests
- property tests: 50 seeds
- crash tests: 50 seeds (small images)
- IPC framing tests
- golden images verify

### Nightly (heavy)

- property tests: 2000+ seeds
- crash tests: 2000+ seeds (bigger images)
- long concurrency runs
- optional fsstress/fsx on Linux FUSE
- benchmarks tracked (non-gating initially)

All failures must print:

- seed
- op index
- fault id
- minimal reproduction script

## 11. Reproducibility Contract

Every test run must be reproducible with:

- seed
- image size
- workload id
- fault injection plan

CLI standard for harness tools:

```text
--seed <u64>
--steps <n>
--image <path>
--size <bytes>
--fault <plan>
--repro <file>
```

`--repro` writes a single file containing all parameters, so bugs can be replayed exactly.

## 12. Deliverables Checklist (v1 Exit Criteria)

Must pass:

- 1000+ property sequences with invariants
- 1000+ crash injection runs with deterministic replay
- rename atomicity suite
- fsync/fdatasync durability suite
- Linux FUSE functional suite
- GaoOS transport suite
- golden image verify on at least GaoOS + Linux

- Document Version: 1.0
- Applies to GaoFS 0.1.x
