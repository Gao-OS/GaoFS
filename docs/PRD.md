# GaoFS v1 – Product Requirement Document

## 1. Overview

GaoFS is a userspace-first filesystem designed for GaoOS (exokernel architecture), with future support for Linux, FreeBSD, and macOS.

GaoFS v1 prioritizes:

**Correctness > Crash Consistency > Testability > Portability > Performance**

This document defines the scope, constraints, non-goals, and success criteria for GaoFS v1.

## 2. Vision

GaoFS aims to provide:

- A single portable on-disk format
- Strong crash recovery guarantees
- Clear durability semantics
- Userspace-first architecture (service restart friendly)
- Cross-platform mount capability

GaoFS is not designed to compete with ZFS or btrfs in features.  
It is designed to be reliable, auditable, and evolvable.

## 3. Target Platforms (Priority Order)

### Phase 1 (Primary Target)

- GaoOS userspace filesystem server

### Phase 2

- Linux (FUSE-based adapter)

### Phase 3

- FreeBSD (FUSE)

### Phase 4

- macOS (macFUSE)

All platforms must share the same disk format.

## 4. Architecture Principles

### 4.1 Userspace Authority

The filesystem server is the single consistency authority.

Clients do not maintain independent metadata state.

### 4.2 Portable Core

All disk logic lives in `gaofs-core`.

No OS-specific code in core.

### 4.3 Strict Layer Separation

| Layer | Responsibility |
| --- | --- |
| core | Disk format, journal, allocator, btree |
| server | Transactions, VFS semantics |
| transport | IPC / shared memory |
| adapters | OS VFS/FUSE translation |
| tools | Offline utilities |

## 5. Scope (v1 Requirements)

### 5.1 Supported File Types

- Regular files
- Directories

### 5.2 Required Operations

- create
- open
- read
- write
- pwrite
- truncate
- rename (atomic)
- unlink
- mkdir
- rmdir
- readdir
- stat
- fsync
- fdatasync

### 5.3 Durability Semantics

Durability must follow:

| Operation | Crash Guarantee |
| --- | --- |
| write | May be lost |
| fdatasync | Data durable |
| fsync | Data + metadata durable |
| rename | Atomic |

No operation may corrupt metadata structures.

## 6. Crash Consistency Model

GaoFS v1 uses:

- Metadata journaling (WAL)
- Checkpoint mechanism
- Deterministic replay

After crash:

- Journal must replay safely
- Filesystem must mount without structural corruption
- Orphans must be detectable
- Double allocation must not occur

## 7. Non-Goals (v1 Excluded Features)

The following are explicitly excluded from v1:

- Snapshots
- Compression
- Encryption
- Deduplication
- Distributed mode
- Copy-on-write data blocks
- Advanced ACL
- Full xattr support
- Online resize
- Defragmentation tools

## 8. Disk Format Requirements

- Single superblock
- Journal area
- Metadata area
- Data area
- Allocator bitmap
- Checkpoint region

Superblock must contain:

- magic
- version
- block_size
- feature flags (`compat`, `ro_compat`, `incompat`)
- journal info
- checksum

Future expansion must be feature-flag gated.

## 9. Tooling Requirements

The following tools are mandatory:

- mkfs.gaofs
- fsck.gaofs
- dump.gaofs

Tools must:

- Operate independently of server
- Support raw block device
- Support image file
- Detect incompatible feature flags

## 10. Testing Requirements

Before declaring v1 usable:

- 1000+ random operation sequences without invariant violation
- 1000+ crash injection runs with successful replay
- rename atomicity tests
- fsync durability tests
- No metadata corruption under fault injection

Crash simulation must include:

- Server kill
- Power-loss simulation
- Partial block write
- Reordered writes

## 11. Performance Targets (v1 Conservative)

Relative to ext4 on Linux (baseline):

- Metadata operations ≥ 50%
- Sequential IO ≥ 70%
- Replay time ≤ 3s per 1GB journal

Performance is secondary to correctness.

## 12. Security Model (v1)

- POSIX-style uid/gid/mode bits
- No advanced ACL
- Server enforces capability mapping on GaoOS
- No encryption in v1

## 13. Upgrade & Compatibility

Superblock must define:

- compat
- ro_compat
- incompat

Rules:

- Unknown incompat → refuse mount
- Unknown ro_compat → read-only mount
- Unknown compat → ignore

Backward compatibility within v1 minor versions is required.

## 14. Success Criteria

GaoFS v1 is considered complete when:

- GaoOS server is stable
- Linux FUSE adapter mounts and passes functional tests
- fsck detects structural errors correctly
- Crash recovery is deterministic
- Disk format is frozen and documented

## 15. Out of Scope for This Document

- IPC protocol details
- Disk layout byte-level specification
- Journal record encoding
- Allocator algorithm specifics

These are defined in separate documents:

- ARCH.md
- DISK_FORMAT.md
- CONSISTENCY.md

## Status

- Document Version: v1.0-draft
- GaoFS Version Target: 0.1.0
- State: Architecture Definition Phase
