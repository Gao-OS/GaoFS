# Porting Guide (Draft)

## Portability Boundary
- Core format and validation logic stay in `gaofs-core`.
- OS-specific I/O and service integration live in adapters (`server` and future platform layers).

## Initial Targets
- GaoOS (primary)
- Linux
- FreeBSD
- macOS

## Porting Checklist
1. Implement block device adapter with required alignment/flush semantics.
2. Validate endian and sector assumptions.
3. Run mkfs/fsck corpus tests on target platform.
4. Verify restart/recovery behavior under abrupt termination tests.
