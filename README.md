# GaoFS

GaoFS is a userspace-first filesystem designed for GaoOS (exokernel architecture),
with planned support for Linux, FreeBSD, and macOS.

## Goals

- Crash-consistent
- Single on-disk format
- Cross-platform
- Strong testing discipline
- Designed for service restart scenarios

## Status

Pre-alpha. Initial monorepo scaffold with architecture drafts.

## Components

- `gaofs-core` (portable Zig library)
- `gaofs-server` (GaoOS-first userspace FS service)
- `mkfs.gaofs`
- `fsck.gaofs`
- `dump.gaofs`

## Prerequisites

- Zig 0.12.0 or newer

## Quickstart

```bash
zig build
./zig-out/bin/mkfs.gaofs
./zig-out/bin/fsck.gaofs
./zig-out/bin/dump.gaofs
./zig-out/bin/gaofs-server
```

If `zig` is not installed locally, install Zig first and rerun the commands above.
