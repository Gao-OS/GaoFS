# GaoFS v1 – On-Disk Format (Frozen)

- Document status: Frozen for v1 (0.1.x)
- Endianness: Little-endian for all integer fields
- Block size: 4096 bytes fixed (v1)
- Sector assumptions: may be 512/4K; on-disk atomicity not assumed beyond sector size (torn writes possible)

## 0. Terminology

- **Block**: 4096 bytes unit of allocation and addressing.
- **LBA**: logical block address in GaoFS block units (4096B), not device sectors.
- **UUID**: 16 bytes.
- **CRC32C**: Castagnoli polynomial checksum.
- **Feature flags**: `compat`, `ro_compat`, `incompat` bitsets as in ext* family semantics.

## 1. High-Level Layout

A GaoFS volume is a linear array of 4K blocks:

```text
Block 0:   Primary Superblock (SB0)
Block 1:   Reserved (SB0 copy / future)
Block 2..J: Journal Area (WAL)
Next:      Checkpoint Area (CP)
Next:      Metadata Area (BTrees, inodes, dirents, extent trees)
Next:      Allocator Bitmap Area (AB)
Next:      Data Area (file data blocks)
Last:      Backup Superblock (SBL)  (optional but REQUIRED in v1 for recovery)
```

### v1 Required Regions

- Primary superblock at block 0
- Journal area: contiguous region
- Checkpoint area: contiguous region
- Allocator bitmap: contiguous region
- Backup superblock: last block of the volume

Tools must refuse to create a v1 volume without backup superblock.

## 2. Addressing and Validity Rules

- All persistent pointers are block numbers (`u64`) unless otherwise stated.
- A “null pointer” is `0` only where explicitly permitted (never for region starts).
- Any pointer that falls outside `[0, total_blocks)` is corruption.
- All variable-length records are length-prefixed and must be bounds-checked.

## 3. Superblock (Block 0 and Last Block)

### 3.1 Superblock Layout (fixed header)

Superblock occupies exactly one block. Fields are packed at the beginning; remaining bytes reserved (must be zero on `mkfs`).

| Offset | Size | Field | Type | Notes |
| --- | --- | --- | --- | --- |
| 0 | 8 | magic | u64 | ASCII `"GAOFS\0\0\0"` encoded as u64 constant |
| 8 | 4 | version_major | u32 | v1: 1 |
| 12 | 4 | version_minor | u32 | v1: 0+ |
| 16 | 4 | block_size | u32 | must be 4096 |
| 20 | 4 | sb_flags | u32 | reserved; must be 0 in v1 |
| 24 | 8 | total_blocks | u64 | volume size in 4K blocks |
| 32 | 16 | fs_uuid | [16]u8 | |
| 48 | 16 | label | [16]u8 | UTF-8, NUL padded |
| 64 | 8 | created_unix_ns | u64 | |
| 72 | 8 | compat | u64 | feature flags |
| 80 | 8 | ro_compat | u64 | feature flags |
| 88 | 8 | incompat | u64 | feature flags |
| 96 | 8 | journal_start | u64 | block index |
| 104 | 8 | journal_blocks | u64 | length in blocks |
| 112 | 8 | checkpoint_start | u64 | block index |
| 120 | 8 | checkpoint_blocks | u64 | length in blocks |
| 128 | 8 | meta_start | u64 | block index |
| 136 | 8 | meta_blocks | u64 | length in blocks (can be 0 = “until bitmap”) |
| 144 | 8 | bitmap_start | u64 | block index |
| 152 | 8 | bitmap_blocks | u64 | length in blocks |
| 160 | 8 | data_start | u64 | first data block index |
| 168 | 8 | root_inode_id | u64 | inode id of `/` |
| 176 | 8 | checkpoint_seq | u64 | last committed checkpoint seq |
| 184 | 8 | journal_seq | u64 | last committed journal seq |
| 192 | 4 | sb_crc32c | u32 | CRC32C of bytes `[0..192)` with this field zeroed |
| 196 | 4 | header_size | u32 | must be 196 in v1 (size of bytes before this field) |
| 200 | … | reserved | bytes | must be zero |

### 3.2 Superblock Rules

- SB0 and SBL must match (except `sb_crc32c`), else mount requires `fsck`.
- `block_size != 4096` => incompat.
- `version_major != 1` => incompat.
- Unknown incompat bits => refuse mount.
- Unknown ro_compat bits => allow read-only mount.
- Unknown compat bits => ignore.

## 4. Feature Flags (v1)

### 4.1 incompat bits (v1)

- bit 0: `INCOMPAT_FIXED_4K` (must be set in v1)
- bit 1: `INCOMPAT_CRC32C` (must be set in v1)
- bit 2: `INCOMPAT_WAL_V1` (must be set in v1)
- bits 3..63: reserved

### 4.2 ro_compat bits (v1)

none defined in v1 (all zero)

### 4.3 compat bits (v1)

none defined in v1 (all zero)

## 5. Checkpoint Area (CP)

Checkpoint is the authoritative “mount root” state after journal replay. It allows bounded replay time and fast mount.

### 5.1 Checkpoint Record (CPR)

Checkpoint area contains an append-only ring of fixed-size checkpoint blocks. Each checkpoint record begins at a block boundary and occupies exactly 1 block (v1).

| Offset | Size | Field | Type | Notes |
| --- | --- | --- | --- | --- |
| 0 | 8 | magic | u64 | `"GAOCP\0\0\0"` |
| 8 | 8 | seq | u64 | monotonically increasing |
| 16 | 8 | timestamp_unix_ns | u64 | |
| 24 | 8 | meta_root_btree | u64 | block pointer to metadata root btree node |
| 32 | 8 | inode_btree_root | u64 | block pointer |
| 40 | 8 | dir_btree_root | u64 | block pointer |
| 48 | 8 | extent_btree_root | u64 | block pointer (optional; can be 0 if in inode tree) |
| 56 | 8 | alloc_bitmap_epoch | u64 | increments when bitmap rewritten |
| 64 | 8 | alloc_bitmap_root | u64 | block pointer or 0 (v1 uses fixed bitmap region → set 0) |
| 72 | 8 | journal_tail_seq | u64 | lowest journal seq still needed |
| 80 | 8 | journal_head_seq | u64 | highest included in this checkpoint |
| 88 | 4 | crc32c | u32 | CRC32C of `[0..88)` with this field zeroed |
| 92 | … | reserved | bytes | must be zero |

### 5.2 Checkpoint Selection

On mount:

- Scan CP area for valid records (magic + crc).
- Choose record with max seq.
- Replay journal from `journal_tail_seq..` to bring state to `journal_head_seq` and beyond.

## 6. Journal (WAL) Area

Journal is metadata-only WAL in v1. Data blocks are written outside journal; durability is controlled by server via flush ordering.

### 6.1 WAL Block Types

Journal area is a sequence of 4K blocks, each block is one of:

- `WAL_HDR` (stream header / segment header)
- `WAL_REC` (record payload block)
- `WAL_PAD` (padding)

v1 uses a record stream with variable-length records. Records may span multiple blocks.

### 6.2 WAL Segment Header (WAL_HDR)

At the start of the journal area and optionally periodically.

| Offset | Size | Field | Type |
| --- | --- | --- | --- |
| 0 | 8 | magic | u64 (`"GAOWAL\0\0"`) |
| 8 | 8 | base_seq | u64 |
| 16 | 8 | block_index | u64 |
| 24 | 8 | reserved | u64 (0) |
| 32 | 4 | crc32c | u32 |
| 36 | … | reserved | zero |

### 6.3 WAL Record Header (inside WAL_REC stream)

Each record is length-prefixed with fixed header bytes `header_bytes = 28`:

| Offset | Size | Field | Type | Notes |
| --- | --- | --- | --- | --- |
| 0 | 4 | rec_len | u32 | total bytes following this field |
| 4 | 2 | rec_type | u16 | enum |
| 6 | 2 | rec_flags | u16 | reserved |
| 8 | 8 | seq | u64 | record sequence |
| 16 | 8 | txn_id | u64 | transaction identifier |
| 24 | 4 | payload_crc32c | u32 | CRC32C of payload bytes |
| 28 | rec_len-24 | payload | bytes | payload bytes only |

Records may not cross end of journal area; wrap uses `WAL_PAD`.

### 6.4 Record Types (v1)

- `TXN_BEGIN`
- `TXN_PUT` (key/value insert/update into a btree)
- `TXN_DEL` (key delete from btree)
- `TXN_ALLOC` (mark blocks allocated)
- `TXN_FREE` (mark blocks freed)
- `TXN_COMMIT` (commit marker)
- `CHECKPOINT_HINT` (optional optimization)

Rule: A transaction is applied on replay only if `TXN_COMMIT` exists and all record CRCs validate.

## 7. Metadata Trees

v1 defines three logical BTrees, all stored in the metadata region:

- Inode BTree: `inode_id -> inode_record`
- Dirent BTree: `(parent_inode_id, name) -> child_inode_id`
- Extent BTree: `(inode_id, file_offset) -> (block, len)` (optional; can be embedded for small files, but v1 freezes separate tree)

All BTrees share the same node format.

### 7.1 BTree Node (one block)

Each node is exactly 4096 bytes.

| Offset | Size | Field | Type |
| --- | --- | --- | --- |
| 0 | 8 | magic | u64 (`"GAOBTR\0\0"`) |
| 8 | 2 | level | u16 |
| 10 | 2 | key_len | u16 |
| 12 | 2 | val_len | u16 |
| 14 | 2 | flags | u16 |
| 16 | 4 | nkeys | u32 |
| 20 | 8 | self | u64 |
| 28 | 8 | right_sibling | u64 |
| 36 | 4 | crc32c | u32 |
| 40 | … | payload | bytes |

Payload format:

- Header+arrays are packed.
- If internal: `nkeys` keys + `nkeys+1` child pointers (`u64`).
- If leaf: `nkeys` keys + `nkeys` values.

Nodes are fixed key/value lengths per tree (v1).

Any unused tail bytes must be zero.

### 7.2 Fixed Key/Value Sizes (v1)

Inode tree:

- key: `inode_id` (`u64`) → `key_len = 8`
- value: `inode_record` (256 bytes fixed, see below) → `val_len = 256`

Dirent tree:

- key: `parent_inode_id` (`u64`) + `name_hash` (`u64`) + `name_len` (`u16`) + `name_bytes` (`<=240`)  
  v1 freezes max name 240 bytes and `key_len = 8+8+2+240 = 258` (padded)
- value: `child_inode_id` (`u64`) → `val_len = 8`

Extent tree:

- key: `inode_id` (`u64`) + `file_off` (`u64`) → `key_len = 16`
- value: `phys_block` (`u64`) + `len_blocks` (`u32`) + `flags` (`u32`) → `val_len = 16`

Note: Dirent key includes both hash and bytes to avoid hash collision ambiguity. Names shorter than 240 bytes are zero-padded in-key to preserve fixed key length.

## 8. Inode Record (fixed 256 bytes)

Stored as value in inode btree.

| Offset | Size | Field | Type |
| --- | --- | --- | --- |
| 0 | 8 | inode_id | u64 |
| 8 | 4 | mode | u32 |
| 12 | 4 | uid | u32 |
| 16 | 4 | gid | u32 |
| 20 | 4 | nlink | u32 |
| 24 | 8 | size_bytes | u64 |
| 32 | 8 | atime_ns | u64 |
| 40 | 8 | mtime_ns | u64 |
| 48 | 8 | ctime_ns | u64 |
| 56 | 4 | flags | u32 |
| 60 | 4 | rdev | u32 |
| 64 | 8 | inline_extent_count | u64 | must be 0 in v1 (reserved for future inline extents) |
| 72 | 8 | reserved0 | u64 |
| 80 | 16 | reserved_uuid | [16]u8 |
| 96 | 160 | reserved | bytes |
| 256 | - | end | |

v1 only supports:

- regular files
- directories

Special files are out of scope (must not appear; `fsck` flags as error).

## 9. Directory Entries

- Directory entries are represented solely by the Dirent BTree.
- A directory’s children are all keys with `parent_inode_id = dir_inode`.
- `readdir` is implemented by scanning a key range (ordered by `name_hash,name_bytes`).
- `"."` and `".."` are virtual (computed), not stored.

## 10. Extents and Data Blocks

### 10.1 Extent Value Semantics

Extent tree maps `(inode_id, file_offset) → (phys_block, len_blocks)`.

Rules:

- `file_offset` is byte offset, must be multiple of `block_size`.
- `len_blocks > 0`, extent covers `len_blocks * 4096` bytes.
- Extents must not overlap within an inode.
- Extents must lie in data region: `phys_block >= data_start`.

Sparse files:

- Absence of extent implies zeros for that range.

## 11. Allocator Bitmap

v1 uses a fixed bitmap region `[bitmap_start, bitmap_start+bitmap_blocks)`.

- One bit per block in the entire volume.
- Bit = 1 means allocated.
- Bits for superblock/journal/checkpoint/meta/bitmap themselves must be pre-marked allocated in `mkfs`.

Bitmap format:

- Bitmap is raw bits, little-endian within bytes.
- First bit corresponds to block 0.

`fsck` must verify:

- Every block referenced by extents/metadata is marked allocated.
- No allocated block is referenced twice (except metadata blocks referenced through btrees by design).

## 12. Checksums and Validation

### 12.1 CRC32C Rules

- Superblock: crc covers header bytes `[0..192)` with `sb_crc32c=0` during compute.
- Checkpoint: crc covers `[0..88)` with field zeroed.
- BTree node: crc covers full block with field zeroed.
- WAL record: `payload_crc32c` covers payload only.

### 12.2 Corruption Handling

Any checksum failure => corruption.

Mount policy (v1):

- if SB0 invalid but SBL valid: recover from SBL and require fsck
- if both invalid: refuse mount
- if WAL corrupted: replay stops at last valid committed txn; require fsck
- if btree node corrupted: require fsck; server must not “guess”

## 13. Mount Algorithm (v1)

1. Read SB0 and SBL; validate CRC; reconcile.
2. Validate feature flags and region boundaries.
3. Load latest checkpoint record.
4. Replay journal from checkpoint tail to end, applying only committed txns.
5. Mount with resulting roots: inode/dirent/extent btrees.

## 14. Format Compatibility Rules

- Major version bump indicates incompatible format change.
- Minor version bump may add:
  - new compat/ro_compat features
  - new WAL record types that are gated by flags

Tools must implement:

- refuse on unknown incompat
- allow RO on unknown ro_compat

## 15. mkfs Defaults (v1)

Recommended defaults for v1 tooling:

- `block_size = 4096`
- `journal_blocks = max(16384 blocks, 1% of volume)` (cap to a sane upper bound)
- `checkpoint_blocks = 1024 blocks` (ring)
- `bitmap_blocks = ceil(total_blocks / (4096*8))`
- `meta_start` immediately after checkpoint; `meta_blocks` can be “until bitmap”
- `data_start` immediately after bitmap

## 16. Frozen Constraints (v1 “do not change”)

- 4K block size fixed
- Superblock `header_size` must be 196
- Inode record size fixed 256
- BTree node is exactly 1 block with CRC field at offset 36
- Backup superblock at last block is mandatory
- WAL is metadata-only with commit marker semantics
