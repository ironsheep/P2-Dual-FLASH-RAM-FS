# Technical Debt Log

This document tracks known technical debt, potential optimizations, and deferred improvements.

---

## TD-001: PSRAM Streaming Mode (Option B)

**Status**: Deferred
**Priority**: Low (revisit if throughput issues observed)
**Created**: 2026-01-08

### Current Implementation (Option A)

Block-based PSRAM access with 4KB blocks:
- Command + address sent for each block
- CS# cycled between blocks (satisfies 8µs refresh constraint)
- Simple, consistent with Flash block model

### Potential Optimization (Option B)

Streaming mode with address auto-increment:
- Single command + address at start of transfer
- CS# briefly cycled every ~2KB for refresh (no re-addressing)
- Address auto-increments across CS# pauses

### Performance Impact

For a 1.2MB video buffer (640×480×4):

| Metric | Option A (Current) | Option B (Optimized) |
|--------|-------------------|---------------------|
| Command/address overhead | ~4.2KB | ~7 bytes |
| Estimated time @ 300MB/s | ~4.05ms | ~4.00ms |
| Overhead difference | ~1-2% slower | Baseline |

### When to Revisit

Consider implementing Option B if:
- Display refresh rates are not meeting targets
- Profiling shows PSRAM transfer is the bottleneck
- Users report throughput issues with large contiguous files
- PWM/DMA applications need tighter timing margins

### Implementation Notes

To implement Option B:
1. Modify PSRAM PASM driver to support streaming mode
2. Add internal CS# cycling within single transfer (every ~2KB)
3. Use PSRAM's address auto-increment feature
4. Only applies to `stream_write()`/`stream_read()` - regular file I/O stays block-based

### Decision Rationale

Option A chosen for initial release because:
- Simpler implementation
- Consistent block model across Flash and RAM
- 1-2% overhead is acceptable for most use cases
- Can be optimized later without API changes

---

## Template for New Entries

```markdown
## TD-XXX: Title

**Status**: Deferred | In Progress | Resolved
**Priority**: Low | Medium | High
**Created**: YYYY-MM-DD
**Resolved**: YYYY-MM-DD (if applicable)

### Current Implementation
[Description of current approach]

### Potential Improvement
[Description of deferred optimization]

### When to Revisit
[Conditions that would trigger revisiting this debt]

### Decision Rationale
[Why this was deferred]
```
