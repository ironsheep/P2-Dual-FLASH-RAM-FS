# Regression Test Status

**Project:** P2 Dual Flash/RAM Filesystem Driver
**Last Updated:** 2026-01-10

## Test Suites Overview

| Test Suite | Tests | Pass | Fail | Status |
|------------|-------|------|------|--------|
| RT_flash_mount_handle_tests | 59 | 59 | 0 | PASS |
| RT_ram_mount_handle_tests | 54 | 49 | 5 | IN PROGRESS |
| **Total** | **113** | **108** | **5** | - |

## Test Suite Details

### RT_flash_mount_handle_tests.spin2 (Flash F: Drive)

**Status:** PASS (59/59)

Tests the Flash filesystem (F:) mount, handle, and format operations:

- **Not Mounted Tests (22 tests):** Verify all operations fail gracefully when filesystem is not mounted
  - unmount(), serial_number(), open(), open_circular(), rename(), delete()
  - exists(), file_size(), stats(), flush(), close(), seek()
  - write(), wr_byte(), wr_word(), wr_long(), wr_str()
  - read(), rd_byte(), rd_word(), rd_long(), rd_str()

- **Mount/Format Tests (4 tests):** Basic mounting and formatting
  - mount() initializes both Flash and RAM
  - format(DRIVE_F) clears Flash filesystem
  - stats() verifies 0 files, 3,968 free blocks
  - directory() confirms empty after format

- **Handle Exhaustion Tests (11 tests):** Verify 4-handle limit
  - Open 4 files successfully (handles 0-3)
  - 5th open returns E_NO_HANDLE
  - Close all 4 files successfully
  - format() cleanup

- **Bad Handle Tests (13 tests):** Operations with invalid handle $1234
  - All operations return E_BAD_HANDLE appropriately

- **File Operations Tests (9 tests):** Basic CRUD operations
  - Create file, write data, verify exists
  - Check file_size() returns correct value
  - rename() changes filename (verified old gone, new exists)
  - delete() removes file
  - stats() confirms 0 files after cleanup

### RT_ram_mount_handle_tests.spin2 (RAM R: Drive)

**Status:** IN PROGRESS (49/54 - 5 failures)

Tests the RAM/PSRAM filesystem (R:) mount, handle, and format operations:

- **Not Mounted Tests (22 tests):** Same coverage as Flash - PASS
- **Mount/Format Tests (4 tests):** Same coverage as Flash - PASS
- **Handle Exhaustion Tests (5 tests):** FAILING - E_FILE_OPEN incorrectly returned
- **Bad Handle Tests (13 tests):** Same coverage as Flash - PASS
- **File Operations Tests (10 tests):** PASS

**Known Issue:** `is_file_open_device()` reads filename CRC from storage, but `finish_open_write()` uses buffered writes. The function should compare against `hFilename` (in-memory) instead of reading from unwritten PSRAM blocks.

## Hardware Configuration

- **Platform:** P2 Edge 32MB (P2-EC32MB)
- **Flash:** W25Q128JVSIM (16MB, 3,968 usable blocks @ 4KB each)
- **PSRAM:** APS6404L-3SQR (8MB × 4 chips = 32MB, 8,192 blocks @ 4KB each)
- **Block Size:** 4,096 bytes
- **Max Open Files:** 4 simultaneous handles

## Running Tests

```bash
cd tests/
./run_now.sh
```

The `run_now.sh` script is configured by the development process to run the current test under development.

## Bug Fixes Applied This Session

1. **Mount Check Logic (31 occurrences):** Changed `ifnot flashMounted and ramMounted` to `ifnot (flashMounted or ramMounted)` - Spin2 operator precedence required parentheses

2. **write() Error Returns:** Changed to return error code instead of 0 on failure

3. **rename() elseif Chain:** Reordered validation checks so Flash rename actually executes

4. **get_file_head_signature_device() Buffer Overflow:** Fixed reading 8 bytes into 4-byte variable

## Planned Test Suites (from TASK 17-19)

| Suite | Est. Tests | Description |
|-------|------------|-------------|
| RT_ram_read_write_tests | 100+ | rd/wr_byte/word/long/str on R: |
| RT_ram_read_write_block_tests | 30+ | Multi-block spanning operations |
| RT_ram_read_seek_tests | 80+ | SEEK_SET/CUR/END operations |
| RT_ram_write_append_tests | 100+ | Append mode testing |
| RT_ram_circular_tests | 250+ | Circular buffer files on R: |
| RT_ram_read_modify_write_tests | 100+ | Read-modify-write patterns |
| RT_ram_8cog_tests | 200+ | 8-cog concurrent R: access |
| RT_flash_compat_tests | 780+ | Port existing Flash tests with F: prefix |
| RT_integration_tests | TBD | Mixed F:/R: operations |
| RT_contiguous_tests | TBD | Contiguous block allocation |
| RT_fragmentation_tests | TBD | Defragmentation testing |
| RT_directory_tests | TBD | Directory operations with dir_fs |

**Target:** 800+ RAM tests, 780+ Flash compatibility tests, additional integration tests
