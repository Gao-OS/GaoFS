# GaoFS v1 – Consistency & Durability Specification

Document Status: Frozen for v1

## 1. Design Goal

GaoFS v1 guarantees:

- No structural corruption after crash
- Deterministic recovery
- Atomic metadata transactions
- Clearly defined durability semantics

GaoFS v1 does NOT guarantee:

- Data persistence without `fsync`
- Write ordering between independent file descriptors
- Snapshot isolation

## 2. Crash Model

The following crash events are assumed possible:

- Process crash (server kill -9)
- Power loss
- Torn write (partial 4K block write)
- Reordered writes (device may reorder)
- Lost flush (write cache not flushed)

The filesystem must remain structurally mountable after any crash.

## 3. Write Ordering Rules

The server is responsible for write ordering.

Core only exposes:

- `write_block()`
- `flush()`

Server must enforce:

### 3.1 Metadata Transaction Rule

For any metadata transaction:

1. Append WAL records
2. Flush WAL blocks
3. Write modified metadata blocks
4. (Optional) Checkpoint

The WAL must reach stable storage before metadata blocks are written.

Violation results in undefined recovery behavior.

### 3.2 Data Write Rule (`write` without `fsync`)

For:

`write(fd, data)`

Server may:

- Write data block lazily
- Not flush
- Not commit metadata immediately

Crash after write may result in:

- Old data visible
- New data lost
- Partial new data visible (if torn write occurred)

But:

- Metadata must remain consistent

### 3.3 `fdatasync` Rule

For:

`fdatasync(fd)`

Server must:

- Flush data blocks belonging to file
- Ensure extents describing those blocks are journal-committed
- Flush WAL commit record

After crash:

- File data is durable
- File size is durable
- Directory entries may not be durable

### 3.4 `fsync` Rule

For:

`fsync(fd)`

Server must:

- Flush data blocks
- Append WAL records for metadata
- Flush WAL commit
- Ensure parent directory entry is committed

After crash:

- File data durable
- File size durable
- Directory entry durable
- Link count consistent

## 4. Rename Semantics

Rename must be atomic.

For:

`rename(old, new)`

Guarantee:

After crash, exactly one of:

- `old` exists
- `new` exists

Never:

- neither exists
- both point to same inode (unless intended)

Implementation rule:

Rename must be a single WAL transaction:

```text
TXN_BEGIN
  delete old dirent
  insert new dirent
  adjust link counts if needed
TXN_COMMIT
```

## 5. Transaction Semantics

Each metadata change is wrapped in:

```text
TXN_BEGIN
  modifications
TXN_COMMIT
```

Rules:

- `TXN_COMMIT` must be the last record of a transaction
- Replay applies only transactions with valid commit record
- Partial transaction records are discarded

Transactions are:

- Atomic
- Idempotent on replay

## 6. Journal Replay Rules

On mount:

- Load checkpoint
- Replay WAL sequentially

For each transaction:

- If complete and valid → apply
- If incomplete → ignore entirely

Replay must:

- Be deterministic
- Not depend on server runtime state
- Not perform heuristic repair

## 7. Metadata Integrity Guarantees

After crash:

The following must hold:

- BTree node CRC valid
- No double allocation
- No block referenced outside region
- No extent overlap within inode
- Root inode reachable
- Orphan inode detectable

## 8. Orphan Handling

An orphan inode is:

- Inode with `nlink == 0`
- Still referenced in inode tree

During mount:

- Orphans may exist after crash
- `fsck` may move them to `lost+found`
- Server may lazily delete orphans on next mount

## 9. Allocation Consistency

Invariant:

```text
∀ block:
  bitmap(block) == 1
    iff
  block referenced by:
    - metadata
    - extent
    - journal (if live)
```

Violation must be detected by `fsck`.

## 10. Torn Write Handling

Possible scenarios:

- WAL record partially written
- BTree node partially written
- Bitmap block partially written

Rules:

- CRC mismatch → treat as invalid
- Invalid WAL record → stop replay at previous valid commit
- Invalid BTree node → require `fsck`
- Invalid bitmap → require `fsck`

No attempt to reconstruct torn metadata in v1.

## 11. Checkpoint Semantics

Checkpoint may be written periodically.

Checkpoint rule:

- All WAL up to seq N must be flushed
- Metadata state must reflect all txns ≤ N
- Checkpoint record written and flushed

Checkpoint does NOT require full metadata rewrite.

## 12. Idempotency Requirements

Replay must be safe to execute multiple times.

Meaning:

If crash occurs during replay:

Replay again must produce same final state.

No WAL record may:

- Depend on implicit state
- Rely on non-deterministic ordering

## 13. Concurrent Write Semantics

v1 does not guarantee strict POSIX write ordering between different file descriptors.

Within a single file descriptor:

- Writes are applied in call order.

Between descriptors:

- Last committed transaction wins.

## 14. Server Restart Semantics (GaoOS-first)

Server crash (without device crash):

- All committed WAL durable
- Uncommitted transactions discarded
- In-memory caches lost
- Replay required on restart

## 15. Forbidden Behaviors (v1)

The following are strictly forbidden:

- Writing metadata blocks before WAL flush
- Applying WAL records without commit marker
- Modifying bitmap outside transaction
- Performing rename across two transactions
- Updating inode size without journaling

Violation results in format corruption.

## 16. Testability Requirements

The following crash scenarios must pass:

- Crash after WAL append but before flush
- Crash after flush but before metadata write
- Crash after metadata write but before commit
- Crash during checkpoint
- Crash during rename

Each must produce deterministic mount result.

## 17. Durability Matrix Summary

| Operation | Data Durable | Metadata Durable | Dir Entry Durable |
| --- | --- | --- | --- |
| write | No | No | No |
| fdatasync | Yes | Yes (size) | No |
| fsync | Yes | Yes | Yes |
| rename | N/A | Yes | Yes |

## 18. v1 Philosophy

GaoFS v1 chooses:

- Simplicity over cleverness
- Determinism over heuristics
- Journaled metadata over COW
- Strong testability over aggressive optimization

- Document Version: 1.0
- Applies to: GaoFS 0.1.x
