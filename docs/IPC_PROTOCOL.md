# GaoFS v1 – IPC Protocol Specification

Document Status: Frozen for v1

## 1. Goals

The IPC protocol connects:

- Clients (OS adapter / VFS / FUSE)
- GaoFS Server

Design constraints:

- Zero-copy data path
- Versioned protocol
- Transport-agnostic framing
- No filesystem semantics inside transport
- No disk-format knowledge in protocol

## 2. Layer Separation

```text
Adapter (VFS/FUSE)
    ↓
IPC Protocol
    ↓
Transport (shm/posix)
    ↓
Server
```

Transport is replaceable.  
IPC protocol is stable across transports.

## 3. Session Model

Each client establishes a session:

- Session ID (`u64`)
- Independent request ordering
- Independent file handle namespace

Session lifecycle:

`HELLO → AUTH → ACTIVE → CLOSE`

## 4. Message Framing

All messages use fixed-size header + optional payload.

### 4.1 Message Header (64 bytes)

| Offset | Size | Field | Type |
| --- | --- | --- | --- |
| 0 | 4 | magic | u32 (`0x47465331 = "GFS1"`) |
| 4 | 2 | version_major | u16 (1) |
| 6 | 2 | version_minor | u16 |
| 8 | 8 | request_id | u64 |
| 16 | 8 | session_id | u64 |
| 24 | 4 | opcode | u32 |
| 28 | 4 | flags | u32 |
| 32 | 4 | payload_len | u32 |
| 36 | 4 | status | i32 (response only) |
| 40 | 8 | data_len | u64 |
| 48 | 8 | data_handle | u64 |
| 56 | 4 | header_crc32c | u32 |
| 60 | 4 | reserved | u32 (0) |

Header CRC covers bytes `[0..56]` with crc field zeroed.

`payload_len` max in v1 is 1 MiB for metadata/control payloads; bulk data must use `data_handle` + `data_len`.

## 5. Zero-Copy Data Model

For large read/write:

- `data_handle` references a shared memory buffer descriptor.
- `data_len` defines valid bytes.

Transport must support:

- Register buffer
- Map buffer into server space
- Release buffer

For POSIX fallback:

- data may be copied
- `data_handle` ignored

## 6. Opcodes (v1)

### 6.1 Session

| Opcode | Name |
| --- | --- |
| 1 | HELLO |
| 2 | AUTH |
| 3 | CLOSE |

### 6.2 File Operations

| Opcode | Name |
| --- | --- |
| 10 | LOOKUP |
| 11 | CREATE |
| 12 | OPEN |
| 13 | READ |
| 14 | WRITE |
| 15 | TRUNCATE |
| 16 | UNLINK |
| 17 | MKDIR |
| 18 | RMDIR |
| 19 | RENAME |
| 20 | READDIR |
| 21 | STAT |
| 22 | FSYNC |
| 23 | FDATASYNC |
| 24 | RELEASE |

## 7. Payload Structures

All payloads are packed little-endian structs.

### 7.1 LOOKUP

Request payload:

- `parent_inode_id` (`u64`)
- `name_len` (`u16`)
- `name_bytes`

Response payload:

- `inode_id` (`u64`)
- `mode` (`u32`)
- `size` (`u64`)

### 7.2 CREATE

Request:

- `parent_inode_id` (`u64`)
- `mode` (`u32`)
- `name_len` (`u16`)
- `name_bytes`

Response:

- `inode_id` (`u64`)

### 7.3 OPEN

Request:

- `inode_id` (`u64`)
- `flags` (`u32`)

Response:

- `file_handle` (`u64`)

File handle is server-issued and session-scoped.

### 7.4 READ

Request:

- `file_handle` (`u64`)
- `offset` (`u64`)
- `length` (`u64`)

Response:

- data returned via shared memory
- `data_len` set
- payload empty

### 7.5 WRITE

Request:

- `file_handle` (`u64`)
- `offset` (`u64`)
- `length` (`u64`)

Data sent via shared memory buffer.

Response:

- `bytes_written` (`u64`)

### 7.6 RENAME

Request:

- `old_parent` (`u64`)
- `old_name_len` (`u16`)
- `old_name_bytes`
- `new_parent` (`u64`)
- `new_name_len` (`u16`)
- `new_name_bytes`

Response: none

Must map to single server transaction.

### 7.7 FSYNC / FDATASYNC

Request:

- `file_handle` (`u64`)

Response: none

### 7.8 HELLO / AUTH

HELLO request payload:

- `client_protocol_major` (`u16`)
- `client_protocol_minor` (`u16`)
- `flags` (`u32`)
- POSIX only: `uid` (`u32`), `gid` (`u32`)

HELLO response payload:

- `server_protocol_major` (`u16`)
- `server_protocol_minor` (`u16`)
- `session_id` (`u64`)

AUTH request payload:

- GaoOS transport: capability token handle (`u64`)
- POSIX transport: empty payload (HELLO identity already provided)

AUTH response payload:

- empty on success

## 8. Error Model

Status field in header:

- `0` = OK
- Positive values = GaoFS protocol error codes

Protocol error codes (v1):

| Code | Name | Typical adapter mapping |
| --- | --- | --- |
| 2 | GFS_ENOENT | ENOENT |
| 17 | GFS_EEXIST | EEXIST |
| 28 | GFS_ENOSPC | ENOSPC |
| 22 | GFS_EINVAL | EINVAL |
| 5 | GFS_EIO | EIO |
| 11 | GFS_EAGAIN | EAGAIN |

Transport errors use:

- `1000+` range (e.g., malformed frame / disconnected peer)

Adapters are responsible for translating protocol error codes to platform-native errno values.

## 9. Ordering Guarantees

Within a session:

- Requests processed in order unless flagged async.
- WRITE requests may be pipelined.

Across sessions:

- No ordering guarantee.

## 10. Concurrency Model

Server must:

- Serialize metadata mutations
- Allow concurrent READ
- Allow concurrent WRITE to different inodes

## 11. Transport Binding

### 11.1 GaoOS Transport

- Shared memory ring buffer
- Fixed-size descriptor entries
- Doorbell interrupt
- Capability-validated buffers

Zero-copy required.

### 11.2 POSIX Transport

- Unix domain socket control channel
- `mmap` shared buffer region
- Fallback to copy if `mmap` unavailable

## 12. Version Negotiation

HELLO request:

- `client_protocol_major`
- `client_protocol_minor`

Server response:

- `server_protocol_major`
- `server_protocol_minor`

Rules:

- Major mismatch → reject
- Minor mismatch → use `min(client, server)`

## 13. Security Model

All requests bound to session.

- GaoOS: capabilities checked during AUTH
- POSIX: uid/gid passed in HELLO

Server must validate:

- Permissions
- Ownership
- Mode bits

Never trust client-supplied inode IDs blindly.

## 14. Backpressure

If server overloaded:

- Return EAGAIN
- Or stall transport

Transport must support bounded queue.

## 15. Extensibility

Future opcodes must:

- Use new opcode number
- Be guarded by feature flags
- Not break header layout

Reserved header fields must remain zero in v1.

## 16. Determinism Requirement

IPC protocol must not:

- Implicitly change ordering
- Depend on network timing
- Include random fields in requests

Replay of identical request sequence must produce identical server state.

## 17. Frozen v1 Constraints

- 64-byte header fixed
- Little-endian
- `request_id` required for all calls
- `file_handle` session-scoped
- Zero-copy data model required for GaoOS transport

- Document Version: 1.0
- Applies to GaoFS 0.1.x
