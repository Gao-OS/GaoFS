# GaoFS v1 – Architecture Specification

## 1. Architecture Overview

GaoFS is a layered filesystem architecture designed for:

- Userspace-first deployment (GaoOS exokernel)
- Strict portability
- Deterministic crash recovery
- Clear separation of mechanism vs policy

GaoFS is composed of five layers:

```text
+---------------------------+
|        OS Adapter         |
| (VFS / FUSE Translation)  |
+---------------------------+
|        Transport          |
| (IPC / Shared Memory)     |
+---------------------------+
|        Server             |
| (Transactions, Semantics) |
+---------------------------+
|        Core               |
| (Disk Format, Journal)    |
+---------------------------+
|      Block Device         |
+---------------------------+
```

## 2. Design Principles

### 2.1 Core is Pure

`gaofs-core`:

- Contains all on-disk logic
- No OS APIs
- No IPC
- No threading
- No global state

Core must be testable in isolation with in-memory block device.

### 2.2 Server Owns Semantics

`gaofs-server`:

- Implements filesystem semantics
- Owns transaction management
- Owns locking
- Owns metadata cache
- Owns durability decisions

Server is the single authority for metadata consistency.

### 2.3 Transport is Mechanism-Only

Transport:

- IPC channel
- Shared memory
- Capability descriptors

Transport must NOT:

- Implement filesystem semantics
- Inspect metadata structures
- Contain durability logic

### 2.4 Adapter is Translation-Only

Adapters convert OS requests into server RPC calls.

Adapters must NOT:

- Implement journaling
- Modify metadata
- Cache authoritative metadata

## 3. Module Boundaries

### 3.1 Core Layer

#### Responsibilities

- Superblock management
- Journal append & replay
- Metadata B-tree
- Inode storage
- Extent management
- Block allocator
- Checkpoint management

#### Core Exposes

Core provides a deterministic API:

- `init(blockdev)`
- `mount()`
- `create_inode()`
- `lookup()`
- `allocate_blocks()`
- `commit_transaction()`
- `replay()`
- `checkpoint()`

Core does NOT:

- Handle file descriptors
- Enforce POSIX semantics
- Perform path resolution
- Handle IPC
- Spawn threads

### 3.2 Server Layer

#### Responsibilities

- Path resolution
- File descriptor table
- Transaction lifecycle
- Lock management
- Rename atomicity
- `nlink` maintenance
- Cache management
- `fsync` semantics

#### Server Owns

- Concurrency model
- Lock ordering
- Write batching
- Flush scheduling

Server must ensure:

- No concurrent metadata corruption
- Deterministic transaction commit order

### 3.3 Transport Layer

Two transport variants:

#### GaoOS Transport

- Shared memory ring
- Capability descriptors
- Zero-copy buffers
- Doorbell notification

#### POSIX Transport

- Unix socket control channel
- `mmap` shared buffers
- Fallback to copy-based IO if needed

Transport contract:

- Request -> Server
- Response -> Client

Transport must be replaceable without modifying server logic.

### 3.4 Adapter Layer

Adapters map OS interface to server RPC.

Examples:

| Platform | Adapter |
| --- | --- |
| GaoOS | `gaoos_vfs` |
| Linux | `linux_fuse` |
| FreeBSD | `freebsd_fuse` |
| macOS | `macos_fuse` |

Adapters must:

- Convert open/read/write/etc to RPC
- Pass file handle tokens
- Translate error codes

Adapters must not:

- Modify disk structures
- Perform journaling
- Maintain metadata cache

## 4. Concurrency Model

v1 Model: Single Metadata Authority

- All metadata modifications serialized via transaction manager
- Data writes may be concurrent
- Rename and directory operations require exclusive locks

Recommended approach:

- Global journal mutex
- Fine-grained inode locks
- Lock ordering strictly defined

## 5. Transaction Model

Each metadata mutation occurs inside a transaction.

Transaction lifecycle:

```text
begin
  modify structures
  journal append
commit
  flush journal
  update checkpoint (optional)
end
```

Transaction must guarantee:

- Atomic metadata update
- Replay-safe state
- Idempotent recovery

## 6. Crash Recovery Flow

On mount:

```text
read superblock
if journal dirty:
    replay journal
    write checkpoint
mount ready
```

Replay must be:

- Deterministic
- Idempotent
- Bounded in time

## 7. Caching Model

v1 Simplicity Rule

- Metadata cache in server only
- Clients do not cache authoritative metadata
- Cache invalidation unnecessary (single authority)

Future optimization may add client caching via leases.

## 8. IO Flow

### Write Path

```text
client → adapter → transport → server
server:
    begin txn
    modify metadata
    append journal
    write data blocks
    commit
```

### Read Path

```text
client → adapter → transport → server
server:
    resolve inode
    read blocks
    return data
```

## 9. Durability Semantics Enforcement

Server enforces `fsync` behavior:

- `write()`: data may stay volatile
- `fdatasync()`: flush data blocks
- `fsync()`: flush data + journal

Transport does not influence durability.

Core only provides flush primitive.

## 10. Error Handling Policy

Core errors:

- Corruption detected
- Invalid block reference
- Journal checksum mismatch

Server errors:

- `ENOENT`
- `EEXIST`
- `ENOSPC`
- `EINVAL`

Transport errors:

- Disconnected client
- Invalid RPC format

Adapters translate server errors to OS error codes.

## 11. Security Model

- Server validates operations
- GaoOS capabilities map to permission checks
- POSIX mode bits enforced at server level
- No trust in client

## 12. Evolution Strategy

Core versioning must allow:

- Feature-flag gated upgrades
- Safe read-only mount on unknown `ro_compat`
- Strict refusal on unknown `incompat`

Server must validate superblock compatibility before mount.

## 13. Non-Responsibilities

Core does NOT:

- Manage IPC
- Enforce POSIX path resolution
- Handle concurrency

Server does NOT:

- Directly parse disk format
- Modify raw disk without core API

Transport does NOT:

- Inspect filesystem internals

Adapters do NOT:

- Maintain persistent state

## Summary

GaoFS v1 architecture is:

- Layered
- Strictly separated
- Userspace authoritative
- Deterministic under replay
- Cross-platform by design

The boundaries are intentionally rigid to prevent long-term architectural decay.

## Document Status

- Document Status: Draft v1
- Target Version: 0.1.0
