# Dual Flash/RAM File System - Sprint Plan

## Project Overview

Create a unified file system driver for the Parallax P2 that manages:
- **F:** - Flash/EEPROM storage (16MB, ~15.5MB usable) with full wear-leveling
- **R:** - PSRAM storage (32MB) without wear-leveling complexity

## Architecture Decision

### Recommended: Composable Wrapper Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      User Application                        │
├─────────────────────────────────────────────────────────────┤
│                dir_fs.spin2 (Directory Wrapper)              │
│      chdir(), mkdir(), rmdir(), listdir(), getcwd()         │
│      Wraps open/close/read/write with path resolution       │
│                      [OPTIONAL LAYER]                        │
├──────────────────────────┬──────────────────────────────────┤
│                          │                                   │
│     flash_fs.spin2       │        flash_ram_fs.spin2             │
│   (Original - UNCHANGED) │      (New - F: and R:)           │
│                          │                                   │
│   For: P2 Edge Module    │   For: P2 Edge 32MB Module       │
│   (Flash only)           │   (Flash + 32MB PSRAM)           │
│                          │                                   │
├──────────────────────────┼──────────────────────────────────┤
│     SPI Flash            │   SPI Flash    │   PSRAM         │
│     (pins 58-61)         │   (pins 58-61) │   (pins 56-57)  │
└──────────────────────────┴───────────────────────────────────┘
```

### Key Design Principle: Composition Over Modification

The directory wrapper (`dir_fs.spin2`) is a **standalone object** that:
- Sits on top of ANY flat file system
- Takes the underlying FS as a parameter
- Adds virtual directory semantics via path manipulation
- Leaves the underlying driver COMPLETELY UNCHANGED

### Usage Scenarios

**Scenario 1: P2 Edge (Flash only, no RAM)**
```spin2
OBJ
  fs  : "flash_fs"          ' Original driver - UNCHANGED
  dir : "dir_fs"            ' Directory wrapper

PUB main()
  fs.mount()
  dir.init(@fs)             ' Wrapper uses flash_fs underneath

  dir.mkdir("logs/2024")
  dir.chdir("logs/2024")
  handle := dir.open("data.txt", "w")
```

**Scenario 2: P2 Edge 32MB (Flash + RAM)**
```spin2
OBJ
  fs  : "dual_fs"           ' New dual driver
  dir : "dir_fs"            ' SAME directory wrapper!

PUB main()
  fs.mount()
  dir.init(@fs)             ' Wrapper uses dual_fs underneath

  dir.mkdir("R:temp/work")  ' RAM directory
  dir.mkdir("F:logs/2024")  ' Flash directory
  dir.chdir("R:temp/work")
  handle := dir.open("scratch.dat", "w")
```

**Scenario 3: Raw access (no directories)**
```spin2
OBJ
  fs : "flash_fs"           ' Use directly without wrapper

PUB main()
  fs.mount()
  handle := fs.open("myfile.txt", "w")  ' Flat access, no overhead
```

### Why This Approach?

1. **Original flash_fs.spin2 unchanged** - No risk to existing tested code
2. **Reusable wrapper** - Same dir_fs.spin2 works with flash_fs OR dual_fs
3. **Optional** - Users can bypass wrapper for raw flat access
4. **Testable** - Each layer can be tested independently
5. **Future-proof** - New storage backends just need flat file API
6. **Minimal coupling** - Wrapper only depends on standard file API

---

## File Structure: Single-File Design

Following the pattern of `flash_fs.spin2`, each driver is **self-contained in ONE file**:

```
flash_fs.spin2 (Original - ~3,400 lines) - UNCHANGED
├── CON: Constants, error codes
├── VAR: State variables, handles, buffers
├── PUB: Public API (mount, open, read, write, etc.)
├── PRI: Private helpers
└── DAT: SPI Flash PASM driver (embedded)

flash_ram_fs.spin2 (New - estimated ~5,000-6,000 lines)
├── CON: Constants, error codes, drive letters
├── VAR: State for Flash + RAM, handles, buffers
├── PUB: Unified API with F:/R: routing
├── PRI: Flash block layer (from flash_fs)
├── PRI: RAM block layer (new)
├── PRI: Contiguous file management
├── PRI: Fragmentation/compact
├── DAT: SPI Flash PASM driver (copied from flash_fs)
└── DAT: PSRAM PASM driver (incorporated from HDMI reference)

dir_fs.spin2 (Optional wrapper - estimated ~800 lines)
├── CON: Path constants
├── VAR: currentDir state
├── PUB: Directory API (chdir, mkdir, listdir, etc.)
├── PUB: Wrapped file API (open, delete, etc.)
└── PRI: Path resolution utilities
```

### User Include Patterns

**P2 Edge Module (Flash only):**
```spin2
OBJ
  fs  : "flash_fs"          ' ONE file - original, unchanged
  dir : "dir_fs"            ' Optional - adds virtual directories
```

**P2 Edge 32MB Module (Flash + RAM):**
```spin2
OBJ
  fs  : "dual_fs"           ' ONE file - contains both drivers
  dir : "dir_fs"            ' Optional - adds virtual directories
```

**Minimal (no directories):**
```spin2
OBJ
  fs : "dual_fs"            ' Just ONE file, full dual-device access
```

### Why Single-File Matters

| Benefit | Description |
|---------|-------------|
| **Simple inclusion** | One OBJ line, no dependencies |
| **No version conflicts** | All code in one place |
| **Easy distribution** | Copy one file to use |
| **Matches flash_fs pattern** | Familiar to existing users |
| **Self-contained** | PASM drivers embedded, not external |

---

## Sprint 1: Foundation & RAM Block Layer

**Goal**: Create the RAM block layer and basic infrastructure

### Task 1.1: Project Setup
- [ ] Create `src/` directory structure
- [ ] Copy flash_fs.spin2 as reference
- [ ] Create `flash_ram_fs.spin2` main file with drive letter parsing
- [ ] Define shared constants (block sizes, error codes, etc.)

### Task 1.2: RAM Block Driver
- [ ] Create `ram_block.spin2` - low-level PSRAM block operations
- [ ] Implement `ram_read_block(block_addr, p_buffer)`
- [ ] Implement `ram_write_block(block_addr, p_buffer)`
- [ ] Implement `ram_init()` - initialize PSRAM driver
- [ ] Define RAM block size (recommend 4KB to match Flash)
- [ ] Calculate usable blocks: 32MB / 4KB = 8,192 blocks

### Task 1.3: RAM Block State Management
- [ ] Create `RAMBlockStates[]` array (2 bits per block)
- [ ] Create `RAMIDToBlocks[]` translation table
- [ ] Create `RAMIDValid[]` validity flags
- [ ] Implement simple sequential block allocation (no randomization)
- [ ] Skip wear-leveling logic entirely for RAM

### Task 1.4: Format & Mount
- [ ] Implement `format(device)` with selectable target:
  - `DRIVE_F` - format Flash only
  - `DRIVE_R` - format RAM only
  - `DRIVE_BOTH` - format both devices
- [ ] Implement `mount()` - initialize BOTH devices together
  - Scan Flash blocks, rebuild tables
  - Initialize RAM, clear state
  - No independent mounting (design decision)
- [ ] Implement `unmount()` - clean shutdown of both devices

### Task 1.5: Multi-Cog Safety (Critical)

The flash_fs.spin2 uses P2 hardware locks for multi-cog safety. flash_ram_fs.spin2 must also be fully multi-cog safe.

**Flash_fs Pattern** (to replicate):
```spin2
DAT
  fsLock        LONG  -1              ' P2 hardware lock semaphore
  errorCode     LONG  0[8]            ' Per-cog error codes
  fsCogCts      LONG  0[8]            ' Per-cog startup timestamps

PRI acquire_lock()
  repeat while locktry(fsLock) == 0   ' Spin until lock acquired

PRI release_lock()
  lockrel(fsLock)
```

**Dual_fs Locking Strategy**:

Option A: Single lock (simpler)
```spin2
fsLock        LONG  -1    ' One lock for entire file system
                          ' Flash and RAM operations serialize
```

Option B: Dual locks (better parallelism) - RECOMMENDED
```spin2
flashLock     LONG  -1    ' Lock for F: operations
ramLock       LONG  -1    ' Lock for R: operations
                          ' Allows F: and R: access in parallel!
```

**Tasks**:
- [ ] Implement dual-lock pattern (flashLock + ramLock)
- [ ] Per-cog error codes: `errorCode LONG[8]`
- [ ] Lock acquisition in all public methods
- [ ] Lock release on all exit paths (including errors)
- [ ] Handle cross-device operations (acquire both locks)
- [ ] Simplify PSRAM driver - remove per-cog command interface (locks serialize access)
- [ ] Test with RT_ram_8cog_tests.spin2 (200+ tests)

**Multi-Cog Scenarios**:
| Cog 0 Action | Cog 1 Action | Behavior |
|--------------|--------------|----------|
| F: write | F: read | Serialized (flashLock) |
| R: write | R: read | Serialized (ramLock) |
| F: write | R: write | **Parallel!** (different locks) |
| F: write | R: read | **Parallel!** (different locks) |
| copy F: to R: | R: read | Serialized (both need ramLock) |

**Deliverable**: RAM block layer that can allocate, read, write blocks (multi-cog safe)

### Task 1.6: Contiguous Files (Hardware Acceleration)

For hardware peripherals (PWM, DMA, video) that need contiguous memory.

**Key Insight**: Buffers ARE files - just contiguous ones. Same naming, same directory listing, just different allocation strategy.

| Aspect | Regular File | Contiguous File |
|--------|--------------|-----------------|
| Has a name | Yes | Yes |
| In directory listing | Yes | Yes |
| Size at creation | Not required (grows as needed) | **REQUIRED** (fixed at creation) |
| Can grow/append | Yes (adds more blocks) | **No** (size is fixed) |
| Storage | 4KB block chains (scattered) | Single contiguous region |
| Access | File I/O (read/write) | High-speed streaming by address |
| Use case | Data storage | Hardware acceleration |

**Memory Layout** (Unified - no separate regions):
```
PSRAM 32MB - SINGLE UNIFIED POOL:
┌─────────────────────────────────────┐
│ [4KB] [CONTIG 64KB] [4KB] [4KB]     │
│ [4KB] [free      ] [CONTIG 1MB   ]  │
│ [free    ] [4KB] [4KB] [free     ]  │
│ [free                             ] │
└─────────────────────────────────────┘

All allocations from SAME pool:
- Regular files: scattered 4KB blocks (chained, location doesn't matter)
- Contiguous files: N consecutive blocks (must find contiguous run)
- compact() moves regular blocks to consolidate free space
```

**API** (extends file API, not separate):
- [ ] Implement `create_contiguous(p_name, size_bytes) : status`
  - **Size is REQUIRED** - entire region allocated immediately
  - Find N consecutive free blocks in unified RAM pool
  - Create file entry with name (appears in directory)
  - Store size in file metadata
  - Do NOT initialize memory (fast allocation)
  - File cannot grow after creation (fixed size)
  - Returns E_DRIVE_FULL if not enough contiguous space
- [ ] Implement `get_address(p_filename) : psram_addr`
  - Return raw PSRAM address of contiguous file
  - Returns 0 if file not found or not contiguous
  - Works only for R: drive (RAM)
- [ ] Implement `is_contiguous(p_filename) : bool`
  - Check if file is contiguous (vs block chain)
- [ ] Implement `stream_write(psram_addr, p_hub_data, count_longs)`
  - High-speed bulk write using PSRAM streaming
  - Bypasses file system block layer
- [ ] Implement `stream_read(psram_addr, p_hub_data, count_longs)`
  - High-speed bulk read using PSRAM streaming
  - Bypasses file system block layer
- [ ] Track which blocks are part of contiguous files (cannot be individually freed)
- [ ] Store contiguous file metadata in file system (not separate table)

### Task 1.7: Fragmentation Management

**Problem**: As files (regular and contiguous) are created and deleted, free space becomes fragmented. New contiguous allocations may fail even though total free space is sufficient.

**Solution**: Move **regular file blocks** (which can be scattered) to consolidate free space for contiguous allocations.

**Status API**:
- [ ] Implement `contiguous_status() : total_free, largest_free, fragment_count, compactable`
  - `total_free`: Total bytes available in contiguous region
  - `largest_free`: Largest single contiguous block available NOW
  - `fragment_count`: Number of separate free regions (1 = no fragmentation)
  - `compactable`: Largest block possible AFTER compact (potential gain)

- [ ] Implement `fragmentation_percent() : percent`
  - Returns 0-100 indicating fragmentation severity
  - 0% = all free space is one contiguous block
  - 100% = free space is maximally fragmented
  - Formula: `100 - (largest_free * 100 / total_free)`

**Compact Operation** (Incremental - one file per call):
- [ ] Implement `compact() : bytes_reclaimed, largest_available`
  - Move ONE contiguous file to close the topmost gap
  - Update that file's metadata with new address
  - Returns:
    - `bytes_reclaimed`: Space recovered by this move (0 if nothing to do)
    - `largest_available`: Largest allocatable block AFTER this move
  - **WARNING**: Invalidates cached `get_address()` for moved file!

- [ ] Implement `compact_all() : total_reclaimed, largest_available`
  - Convenience method: calls `compact()` repeatedly until no improvement
  - Returns final totals
  - **WARNING**: Invalidates ALL cached `get_address()` results!

- [ ] Implement `compact_needed() : bool`
  - Quick check: is compaction worthwhile?
  - Returns TRUE if `compactable > largest_free * 2` (would double available)

**Usage Example - Incremental** (preferred for real-time systems):
```spin2
' Need 256KB contiguous block
needed := 256 * 1024

repeat
  reclaimed, largest := fs.compact()   ' Move ONE file
  if largest >= needed
    quit                                ' Got enough space!
  if reclaimed == 0
    quit                                ' No more improvement possible

if largest >= needed
  fs.create_contiguous("R:NEWBUF", needed)
  ' Re-fetch any cached addresses that may have moved
  video_addr := fs.get_address("R:VIDEO")
else
  debug("Cannot achieve required size")
```

**Usage Example - Full Compact** (simpler but blocks longer):
```spin2
total, largest, frags, potential := fs.contiguous_status()

if largest < needed AND potential >= needed
  fs.compact_all()                      ' Move all files at once
  ' Must re-fetch ALL cached addresses
  video_addr := fs.get_address("R:VIDEO")
  pwm_addr := fs.get_address("R:PWM")
```

**Block Selection Algorithm** (maximize benefit per move):
```
For each regular file BLOCK that fragments free space:
  benefit = free_space_above + free_space_below

Select block with MAXIMUM combined benefit
Move that block to edge of RAM, merging the two free regions
```

**Example**:
```
┌──────────────┐
│ CONTIG_A     │ (contiguous file - don't move)
├──────────────┤
│ free (50KB)  │
├──────────────┤
│ [blk] [blk]  │ ← regular file blocks (CAN move)
├──────────────┤
│ free (200KB) │
├──────────────┤
│ [blk]        │ ← this block fragments 200KB + 100KB = 300KB ★ MOVE THIS
├──────────────┤
│ free (100KB) │
├──────────────┤
│ CONTIG_B     │ (contiguous file - don't move)
└──────────────┘

compact() moves the fragmenting [blk] to consolidate free space
Result: 200KB + 100KB merge into 300KB contiguous free region
```

**Key Insight**:
- **Regular file blocks**: CAN be moved (they're chained, location doesn't matter)
- **Contiguous files**: DON'T move (hardware may have cached addresses)
- Moving regular blocks creates larger free regions for contiguous allocations

**Implementation Notes**:
- Block selection: choose block with largest (free_above + free_below)
- Each call has predictable timing (one block move)
- Caller controls when to stop (goal met or no improvement)
- `compact_all()` is just a loop around `compact()` for convenience
- If multiple blocks have equal benefit, prefer moving smaller file's block

**Usage Example**:
```spin2
' Create contiguous file for PWM hardware
fs.create_contiguous("R:PWM", 4096)

' Get raw address for hardware driver
pwm_addr := fs.get_address("R:PWM")

' High-speed streaming (bypasses file I/O)
fs.stream_write(pwm_addr, @waveform, 1024)

' Appears in directory like any file
fs.directory(...)  ' Shows: "PWM", "config.dat", "log.txt"

' Delete like any file
fs.delete("R:PWM")
```

**Use Cases**:
- PWM waveform buffers
- Video framebuffers (640×480×4 = ~1.2MB)
- DMA transfer buffers
- Audio sample buffers
- Lookup tables for hardware

**Deliverable**: Contiguous file support for hardware acceleration

---

## Sprint 2: Common File System Layer

**Goal**: Extract device-agnostic code into shared layer

### Task 2.1: File Handle Abstraction (Unified Pool)
- [ ] Create handle structure with 1-bit device flag (F: or R:)
- [ ] Single unified handle pool shared between both devices
- [ ] Update handle allocation to set device flag based on filename
- [ ] Handle lookup returns device type for routing

### Task 2.2: Drive Letter Parsing
- [ ] Implement `parse_drive_letter(p_filename)` returns device + filename
- [ ] Default to F: if no drive letter specified (backward compatible)
- [ ] Validate drive letter (only F: and R: allowed)

### Task 2.3: Block Chain Operations (Device-Agnostic)
- [ ] Extract chain traversal logic
- [ ] Extract file size calculation
- [ ] Extract directory enumeration
- [ ] Make these call device-specific read/write functions

### Task 2.4: CRC and Filename Handling
- [ ] Keep existing CRC routines (shared by both)
- [ ] Keep filename CRC for fast lookups
- [ ] Block CRC applies to both (data integrity)

**Deliverable**: Shared file system logic that routes to correct device

---

## Sprint 3: Unified API Implementation

**Goal**: Complete file operations for both devices

### Task 3.1: Core File Operations
- [ ] Implement `open(p_filename, mode)` with drive routing
- [ ] Implement `close(handle)` with device-aware flush
- [ ] Implement `flush(handle)` for both devices
- [ ] Implement `delete(p_filename)` for both devices
- [ ] Implement `rename(p_cur, p_new)` (same device only)
- [ ] Implement `copy_file(p_src, p_dst)` - cross-device copy helper
  - Handles F: to R: and R: to F: transparently
  - Acquires both locks for cross-device operations
  - Returns bytes copied or error code

### Task 3.2: Read Operations
- [ ] Implement `read(handle, p_buffer, count)`
- [ ] Implement `rd_byte()`, `rd_word()`, `rd_long()`, `rd_str()`
- [ ] Implement `seek(handle, position, whence)`
- [ ] Route to correct device block read

### Task 3.3: Write Operations
- [ ] Implement `write(handle, p_buffer, count)`
- [ ] Implement `wr_byte()`, `wr_word()`, `wr_long()`, `wr_str()`
- [ ] Handle block chain extension
- [ ] Route to correct device block write

### Task 3.4: Query Operations
- [ ] Implement `exists(p_filename)` with drive routing
- [ ] Implement `file_size(p_filename)`
- [ ] Implement `directory()` flat iterator
- [ ] Implement `stats()` - separate stats per device

### Task 3.5: Circular Files (Both Devices)
- [ ] Implement circular file support for F: (already in flash_fs)
- [ ] Implement circular file support for R: (new)
  - Ring buffer behavior - overwrites oldest data when full
  - Same API as Flash: `open_circular()`, size limit at creation
  - Simpler implementation for RAM (no wear-leveling concerns)
- [ ] Ensure consistent API between F: and R: circular files

**Deliverable**: Full flat file API working for both F: and R: drives

---

## Sprint 4: Flash Integration & Wear-Leveling

**Goal**: Integrate existing flash code with new architecture

### Task 4.1: Flash Block Driver Adaptation
- [ ] Create `flash_block.spin2` wrapper around existing SPI code
- [ ] Implement `flash_read_block()` interface
- [ ] Implement `flash_write_block()` with wear-leveling
- [ ] Keep lifecycle bit management for Flash only

### Task 4.2: Flash-Specific Features
- [ ] Maintain random block selection for wear distribution
- [ ] Keep block eviction/relocation logic
- [ ] Keep activation/cancellation for atomic writes
- [ ] Preserve backward compatibility with existing flash files

### Task 4.3: Device Router
- [ ] Create dispatch table for device operations
- [ ] Route format/mount/unmount per device
- [ ] Route block operations per device
- [ ] Handle cross-device copy (F: to R: and vice versa)

**Deliverable**: Flash operations working through new architecture

---

## Sprint 5: Directory Wrapper (dir_fs.spin2)

**Goal**: Create standalone directory wrapper that works with ANY flat file system

### Design: Standalone Composable Object

```spin2
' dir_fs.spin2 - Directory wrapper (works with flash_fs OR dual_fs)
'
' Usage:
'   OBJ
'     fs  : "flash_fs"    ' or "dual_fs"
'     dir : "dir_fs"
'
'   PUB main()
'     fs.mount()
'     dir.init(@fs)
'     dir.chdir("logs")
'     handle := dir.open("data.txt", "w")

VAR
  LONG  pFS                     ' Pointer to underlying file system
  BYTE  currentDir[128]         ' Current working directory path

' ... wrapper methods that call through to pFS ...
```

### Task 5.1: Wrapper Foundation
- [ ] Create `dir_fs.spin2` as standalone object
- [ ] Implement `init(p_filesystem)` - store FS pointer
- [ ] Define method dispatch to underlying FS (open, close, read, write, etc.)
- [ ] Add `currentDir` state variable (128 bytes)

### Task 5.2: Path Resolution
- [ ] Implement `is_absolute_path(p_path)` - detect drive letter or leading `/`
- [ ] Implement `normalize_path(p_path, p_result)` - resolve `.` and `..`
- [ ] Implement `join_path(p_base, p_relative, p_result)` - combine paths
- [ ] Implement `split_path(p_path, p_dir, p_filename)` - separate components
- [ ] Implement `build_full_path(p_relative)` - prepend currentDir

### Task 5.3: Directory Operations (with Super-Root)
- [ ] Implement super-root state (no drive selected)
  - Initial state after `init()` is super-root
  - `listdir()` at super-root shows `F:/` and `R:/` as entries
  - `chdir("F:")` or `chdir("R:")` enters that drive
  - `chdir("..")` from drive root returns to super-root
- [ ] Implement `chdir(p_path)` - change current directory
- [ ] Implement `getcwd(p_buffer)` - get current directory (includes drive if selected)
- [ ] Implement `mkdir(p_path)` - create marker file `"path/.d"`
- [ ] Implement `rmdir(p_path)` - remove if no files with prefix
- [ ] Implement `listdir(p_path, p_callback)` - enumerate entries at path

### Task 5.4: Wrapped File Operations
- [ ] Implement `open(p_filename, mode)` - resolve path, call fs.open()
- [ ] Implement `close(handle)` - pass through to fs.close()
- [ ] Implement `read/write/seek` - pass through to fs methods
- [ ] Implement `delete(p_filename)` - resolve path, call fs.delete()
- [ ] Implement `rename(p_old, p_new)` - resolve paths, call fs.rename()
- [ ] Implement `exists(p_filename)` - resolve path, call fs.exists()
- [ ] Implement `file_size(p_filename)` - resolve path, call fs.file_size()

### Task 5.5: listdir Implementation
- [ ] Scan all files via underlying `directory()` iterator
- [ ] Filter by currentDir prefix
- [ ] Extract unique "next segment" (file or subdirectory name)
- [ ] Distinguish files vs subdirectories (has more `/` after segment)
- [ ] Return entries via callback or iterator pattern

**Deliverable**: Standalone dir_fs.spin2 that adds directory semantics to any flat FS

---

## Development Tooling

### Background: Why run_test.sh Exists

Running P2 tests involves a complex multi-process orchestration:

1. **Compile** (foreground): `pnut-ts -d` compiles with DEBUG support, generating `.bin`
2. **Download** (foreground UI): `pnut-term-ts -r` downloads to RAM and runs
3. **Capture**: As the P2 executes, DEBUG output streams back over serial and is logged automatically to `./logs/debug_*.log`
4. **Monitor** (background): Watch the log for `END_SESSION` marker indicating test completion
5. **Terminate**: Kill the downloader when marker found OR timeout expires
6. **Evaluate**: Parse the log file for test results

**The Problem**: When Claude Code ran these steps manually:
- Background monitor tasks became orphaned
- Unclear when the downloader actually terminated
- Process cleanup was inconsistent
- After 2-3 test runs, the environment became confused with zombie processes

**The Solution**: `run_test.sh` encapsulates all orchestration:
- Single foreground command with predictable behavior
- Automatic process cleanup via trap handlers
- Clear exit codes for pass/fail/timeout
- No orphaned processes
- Claude Code just runs one command and checks the exit code

### Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     run_test.sh <test> <dir> -t <sec>           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. COMPILE (foreground)                                        │
│     pnut-ts -d test.spin2  ──►  test.bin                        │
│                                                                 │
│  2. DOWNLOAD & RUN (foreground, but script manages)             │
│     pnut-term-ts -r test.bin  ──►  P2 executes                  │
│                                    │                            │
│                                    ▼                            │
│  3. CAPTURE (automatic)        DEBUG output ──► logs/debug_*.log│
│                                    │                            │
│  4. MONITOR (background)           │                            │
│     Watch log for END_SESSION ◄────┘                            │
│           │                                                     │
│           ├── Found? ──► Kill downloader ──► Exit 0 (PASS)      │
│           │                                                     │
│  5. TIMEOUT (background)                                        │
│     Sleep <sec> ──► Kill downloader ──► Exit 3 (TIMEOUT)        │
│                                                                 │
│  6. CLEANUP (trap on EXIT)                                      │
│     Kill all child processes, no orphans                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Overview

The project uses TypeScript-based tools for compilation and testing:

| Tool | Purpose | Installation |
|------|---------|--------------|
| `pnut-ts` | Spin2/PASM2 compiler | `npm install -g pnut-ts` |
| `pnut-term-ts` | Download, run, and DEBUG terminal | `npm install -g pnut-term-ts` |
| `run_test.sh` | Automated test runner | `tools/run_test.sh` |

### pnut-ts Compiler

**Usage**: `pnut-ts [options] filename.spin2`

**Key Options**:
```
-d, --debug       Compile with DEBUG support (required for test output)
-l, --list        Generate listing file (.lst)
-m, --map         Generate memory map file (.map)
-o, --output      Specify output file basename
-q, --quiet       Suppress banner and non-error text
-I, --Include     Add preprocessor include directories
```

**Examples**:
```bash
# Compile with DEBUG support
pnut-ts -d mytest.spin2

# Compile with listing and map files
pnut-ts -d -l -m mytest.spin2

# Compile with include path
pnut-ts -d -I ../src mytest.spin2
```

### pnut-term-ts Downloader/Terminal

**Usage**: `pnut-term-ts [options]`

**Key Options**:
```
-r, --ram <file>       Download to RAM and run
-f, --flash <file>     Download to FLASH and run
-p, --plug <device>    Specify PropPlug device node
-b, --debugbaud <rate> Set debug baud rate (default 2000000)
-n, --dvcnodes         List available USB serial devices
-q, --quiet            Suppress banner and non-error text
--ide                  IDE mode for VSCode integration
```

**Examples**:
```bash
# Download to RAM (auto-detects single PropPlug)
pnut-term-ts -r mytest.bin

# List available PropPlug devices
pnut-term-ts -n

# Download to specific PropPlug
pnut-term-ts -r mytest.bin -p P9cektn7

# IDE mode for automation
pnut-term-ts --ide -r mytest.bin
```

**Debug Output**: The terminal captures DEBUG output from the P2 and writes to log files in `./logs/debug_*.log`.

### run_test.sh - Automated Test Runner

**Location**: `tools/run_test.sh`

**Usage**: `./tools/run_test.sh <basename> <srcdir> -t <timeout> [-m] [-l]`

**Arguments**:
| Argument | Required | Description |
|----------|----------|-------------|
| `basename` | Yes | Source file name without .spin2 extension |
| `srcdir` | Yes | Directory containing the source file |
| `-t <sec>` | Yes | Timeout in seconds |
| `-m` | No | Generate memory map file |
| `-l` | No | Generate listing file |

**Exit Codes**:
| Code | Meaning |
|------|---------|
| 0 | Test PASSED (END_SESSION found in log) |
| 1 | Compilation failed |
| 2 | Download/run failed |
| 3 | Timeout (END_SESSION not found) |
| 4 | Usage error |

**How It Works**:
1. Compiles the .spin2 file with DEBUG enabled
2. Starts pnut-term-ts to download and run
3. Monitors `./logs/debug_*.log` for `END_SESSION` marker
4. Terminates when marker found or timeout expires
5. Reports pass/fail and shows last 30 lines of log

**Example**:
```bash
# Run a test with 60-second timeout
./tools/run_test.sh RT_performance_benchmark tests -t 60

# Run with listing file generation
./tools/run_test.sh RT_performance_benchmark tests -t 60 -l -m
```

**Test File Requirements**:
- Must output `END_SESSION` via DEBUG when complete
- Example end-of-test code:
```spin2
PUB end_tests()
  debug("END_SESSION")
  repeat  ' Halt
```

### Task 16.25: Validate Test Script

Before running full test suites, validate that the test automation works:

- [ ] Create minimal test file `tests/RT_script_test.spin2`
  - Just outputs `END_SESSION` via DEBUG
- [ ] Run: `./tools/run_test.sh RT_script_test tests -t 30`
- [ ] Verify:
  - Compilation succeeds
  - Download succeeds
  - Log file created in `tests/logs/`
  - `END_SESSION` detected
  - Exit code is 0
- [ ] Document any issues found

**PREREQUISITE**: P2 hardware connected via PropPlug

---

## Sprint 6: Testing & Optimization

**Goal**: Comprehensive testing and performance tuning

### Task 6.1: RAM Regression Tests (Mirror Flash Test Suite)

The existing flash_fs has comprehensive regression tests in `REFERENCE/FLASH-FS/RegresssionTests/`.
Create equivalent tests for the RAM side to ensure full coverage.

| Flash Test File | RAM Equivalent | Tests |
|-----------------|----------------|-------|
| RT_read_write_tests.spin2 | RT_ram_read_write_tests.spin2 | Basic read/write, wr/rd_byte/word/long/str |
| RT_read_write_block_tests.spin2 | RT_ram_read_write_block_tests.spin2 | Multi-block spanning |
| RT_read_seek_tests.spin2 | RT_ram_read_seek_tests.spin2 | Seek functionality |
| RT_write_append_tests.spin2 | RT_ram_write_append_tests.spin2 | Append mode |
| RT_read_write_circular_tests.spin2 | RT_ram_circular_tests.spin2 | Circular files |
| RT_mount_handle_basics_tests.spin2 | RT_ram_mount_handle_tests.spin2 | Mount, handles, directory |
| RT_read_modify_write_tests.spin2 | RT_ram_read_modify_write_tests.spin2 | R/W extended modes |
| RT_read_write_8cog_tests.spin2 | RT_ram_8cog_tests.spin2 | Multi-cog access |

- [ ] Create `RegresssionTests/` folder for dual_fs
- [ ] Port RT_utilities.spin2 for dual_fs testing
- [ ] Create RT_ram_read_write_tests.spin2 (target: 100+ tests)
- [ ] Create RT_ram_read_write_block_tests.spin2 (target: 30+ tests)
- [ ] Create RT_ram_read_seek_tests.spin2 (target: 80+ tests)
- [ ] Create RT_ram_write_append_tests.spin2 (target: 100+ tests)
- [ ] Create RT_ram_circular_tests.spin2 (target: 250+ tests)
- [ ] Create RT_ram_mount_handle_tests.spin2 (target: 40+ tests)
- [ ] Create RT_ram_read_modify_write_tests.spin2 (target: 100+ tests)
- [ ] Create RT_ram_8cog_tests.spin2 (target: 200+ tests)
- [ ] Verify RAM tests achieve same pass count as Flash equivalents

### Task 6.2: Flash Compatibility Tests
- [ ] Port existing flash tests to work with F: prefix in dual_fs
- [ ] Verify all 780+ existing flash tests still pass
- [ ] Test drive letter parsing edge cases
- [ ] Test error handling for invalid drives

### Task 6.3: Integration Tests
- [ ] Test mixed F:/R: operations in same program
- [ ] Test multi-cog access to both devices
- [ ] Test large file operations on RAM (benefit: speed)
- [ ] Test circular files on both devices
- [ ] Test `format(DRIVE_F)` formats only Flash, preserves RAM
- [ ] Test `format(DRIVE_R)` formats only RAM, preserves Flash
- [ ] Test `format(DRIVE_BOTH)` formats both devices
- [ ] Test `mount()` initializes both devices together

### Task 6.4: Contiguous File Tests
- [ ] Test `create_contiguous()` finds consecutive free blocks
- [ ] Test `get_address()` returns correct PSRAM address
- [ ] Test `is_contiguous()` correctly identifies file type
- [ ] Test contiguous files appear in `directory()` listing
- [ ] Test `delete()` works on contiguous files
- [ ] Test `stream_write()` / `stream_read()` performance
- [ ] Test multiple contiguous files coexist
- [ ] Test contiguous + regular files don't collide
- [ ] Test allocation failure when RAM full
- [ ] Test large contiguous file (1MB+ video buffer)
- [ ] Verify memory is truly contiguous (hardware PWM test)
- [ ] Test `get_address()` returns 0 for regular (non-contiguous) files
- [ ] Test `get_address()` returns 0 for F: drive files

### Task 6.5: Fragmentation Management Tests
- [ ] Test `contiguous_status()` returns correct values
- [ ] Test `fragmentation_percent()` is 0% when no fragmentation
- [ ] Test `fragmentation_percent()` increases after deletions
- [ ] Test `largest_free` correctly identifies biggest gap
- [ ] Test `compactable` shows potential gain
- [ ] Test `compact()` moves exactly ONE file per call
- [ ] Test `compact()` returns `bytes_reclaimed` correctly
- [ ] Test `compact()` returns `largest_available` after move
- [ ] Test `compact()` returns 0, largest when nothing to do
- [ ] Test incremental loop achieves target size
- [ ] Test `compact_all()` moves all files in one call
- [ ] Test `compact_all()` returns total reclaimed + final largest
- [ ] Test `get_address()` returns NEW address after compact
- [ ] Test `compact_needed()` returns TRUE when beneficial
- [ ] Test allocation succeeds after compact where it failed before
- [ ] Test compact selects file with max (gap_above + gap_below)
- [ ] Test compact prefers smaller file when benefit is equal
- [ ] Test compact when no fragmentation (no-op, no error)
- [ ] Stress test: create/delete many files, then compact incrementally

### Task 6.6: Directory Wrapper Tests
- [ ] Test dir_fs with flash_fs underneath
- [ ] Test dir_fs with dual_fs underneath
- [ ] Test `chdir()` with absolute and relative paths
- [ ] Test `chdir("..")` parent navigation
- [ ] Test `mkdir()` creates marker file
- [ ] Test `rmdir()` fails when directory has files
- [ ] Test `rmdir()` succeeds on empty directory
- [ ] Test `listdir()` returns correct entries
- [ ] Test `listdir()` distinguishes files vs subdirectories
- [ ] Test `open()` with relative paths after `chdir()`
- [ ] Test path normalization (`"a/b/../c"` → `"a/c"`)
- [ ] Test cross-device paths: `chdir("F:")` then `open("R:file")`
- [ ] **Super-root tests**:
  - [ ] Test initial state is super-root (no drive selected)
  - [ ] Test `listdir()` at super-root shows `F:/` and `R:/`
  - [ ] Test `chdir("F:")` enters Flash drive root
  - [ ] Test `chdir("R:")` enters RAM drive root
  - [ ] Test `chdir("..")` from `F:/` returns to super-root
  - [ ] Test `getcwd()` at super-root returns `/` or empty
  - [ ] Test `open()` at super-root requires drive prefix

### Task 6.7: Cross-Device Operations
- [ ] Test `copy_file("F:src.txt", "R:dst.txt")` - Flash to RAM
- [ ] Test `copy_file("R:src.txt", "F:dst.txt")` - RAM to Flash
- [ ] Test `copy_file("F:a.txt", "F:b.txt")` - same device copy
- [ ] Test copy of large files (multi-block)
- [ ] Test copy error handling (source not found, dest drive full)
- [ ] Performance comparison: Flash vs RAM
- [ ] Test copy acquires both locks for cross-device

### Task 6.8: Performance Optimization
- [ ] Profile RAM operations vs Flash
- [ ] Optimize RAM block allocation (sequential = fast)
- [ ] Consider larger block size for RAM (8KB? 16KB?)
- [ ] Document performance characteristics

**Deliverable**: Fully tested, optimized dual file system

---

## Sprint 7: Documentation & Demo

**Goal**: Documentation and example applications

### Task 7.1: API Documentation
- [ ] Document flash_fs.spin2 API (original, unchanged)
- [ ] Document flash_ram_fs.spin2 API (new dual-device driver)
- [ ] Document dir_fs.spin2 API (directory wrapper)
- [ ] Document drive letter convention (F:, R:)
- [ ] Document error codes
- [ ] Document limitations and constraints

### Task 7.2: Demo Applications
- [ ] Create `dual_fs_demo.spin2` showing both F: and R: drives
- [ ] Create `dir_fs_demo.spin2` showing directory operations
- [ ] Demo: Log to RAM (fast), archive to Flash (persistent)
- [ ] Demo: RAM as working space, Flash as permanent storage
- [ ] Demo: Directory navigation and listing

### Task 7.3: Configuration Guide
- [ ] Document P2 Edge (flash_fs only) setup
- [ ] Document P2 Edge 32MB (dual_fs) setup
- [ ] Document adding dir_fs wrapper to either configuration
- [ ] Explain when to use each component

### Task 7.4: Migration Guide
- [ ] Document upgrading from flash_fs.spin2 to flash_ram_fs.spin2
- [ ] Explain backward compatibility (no prefix = F:)
- [ ] Explain adding directory support to existing projects

**Deliverable**: Complete documentation and working demos

---

## Hardware Specifications

### Target Module: P2-EC32MB (Part# 64000-ES)

| Component | Chip | Manufacturer | Size | Interface |
|-----------|------|--------------|------|-----------|
| **Flash** | W25Q128JVSIM | Winbond | 16MB (128 Mbit) | SPI |
| **PSRAM** | APS6404L-3SQR-ZR | AP Memory | 32MB (4 × 8MB) | QSPI (16-bit) |
| **MCU** | P2X8C4M64P | Parallax | 512KB Hub RAM | - |

### Pin Assignments (Confirmed from P2KB + Reference Drivers)

**SPI Flash (P58-P61)** - from `flash_fs.spin2`:
```
Pin   Signal      Direction   Description
───   ──────      ─────────   ───────────
P58   SF_MISO     Input       Flash Data Out (DO)
P59   SF_MOSI     Output      Flash Data In (DI)
P60   SF_SCLK     Output      Flash Clock
P61   SF_CS       Output      Flash Chip Select (active low)
```

**PSRAM (P40-P57)** - from `PSRAM_driver_RJA_Platform_1b.spin2`:
```
Pin       Signal       Description
───       ──────       ───────────
P40-P43   Bank 0 SIO   PSRAM Data [3:0] - 8MB
P44-P47   Bank 1 SIO   PSRAM Data [3:0] - 8MB
P48-P51   Bank 2 SIO   PSRAM Data [3:0] - 8MB
P52-P55   Bank 3 SIO   PSRAM Data [3:0] - 8MB
P56       CLK          PSRAM Clock (all 4 chips)
P57       CE#          PSRAM Chip Enable (active low)
```

**microSD (P58-P61)** - shared with Flash:
```
Pin   Flash Signal   SD Signal     Note
───   ────────────   ─────────     ────
P58   SF_MISO        DAT0/MISO     Shared
P59   SF_MOSI        CMD/MOSI      Shared + boot mode select
P60   SF_SCLK        DAT3/CS       Shared
P61   SF_CS          CLK           Shared
```
⚠️ **Note**: Flash and microSD share pins - cannot use simultaneously

**Serial Programming (P62-P63)**:
```
P62   TX    Serial transmit (to PropPlug RX)
P63   RX    Serial receive (from PropPlug TX)
```

### PSRAM Timing Constraints

| Parameter | Value | Note |
|-----------|-------|------|
| Max CS# low time | 8 µs | Must release for DRAM refresh |
| Max clock | 133 MHz | Per APS6404L datasheet |
| Burst rate | >300 MB/s | 16-bit parallel mode |
| Address bits | 25 | 32MB address space |

### Memory Map

```
PSRAM Address Space (32MB):
$0000_0000 - $01FF_FFFF

Flash Address Space (16MB):
$0000_0000 - $00FF_FFFF (but first 512KB reserved for boot)
```

---

## Technical Specifications

### Block Layout (Both Devices)

| Component | Flash (F:) | RAM (R:) |
|-----------|------------|----------|
| Block Size | 4KB | 4KB (matches Flash) |
| Total Blocks | 3,968 | 8,192 |
| Usable Space | ~15.5MB | ~32MB |
| Head Block Data | 3,956 bytes | 3,956 bytes |
| Body Block Data | 4,088 bytes | 4,088 bytes |

### Simplified RAM Block Header

```
RAM Block Header (simplified - no lifecycle bits needed):
Offset  Size    Purpose
0x000   4 bytes Block state + next block ID (no lifecycle)
0x004   ...     Data area
0xFFC   4 bytes CRC (still needed for data integrity)
```

### Drive Letter Convention

| Prefix | Device | Persistence | Speed | Use Case |
|--------|--------|-------------|-------|----------|
| F: | Flash EEPROM | Persistent | Slow | Config, logs, permanent data |
| R: | PSRAM | Volatile | Fast | Temp files, working data, buffers |
| (none) | Flash (default) | Persistent | Slow | Backward compatibility |

### Memory Usage Estimate

```
Flash Management:
- BlockStates[]:     ~1KB (2 bits × 4096 blocks)
- IDToBlocks[]:      ~6KB (12 bits × 4096 IDs)
- IDValid[]:         ~512 bytes (1 bit × 4096 IDs)
- Subtotal:          ~8KB

RAM Management:
- RAMBlockStates[]:  ~2KB (2 bits × 8192 blocks)
- RAMIDToBlocks[]:   ~12KB (13 bits × 8192 IDs)
- RAMIDValid[]:      ~1KB (1 bit × 8192 IDs)
- Subtotal:          ~15KB

Virtual Directory State (in dir_fs wrapper):
- currentDir[F:]:    128 bytes (current path for Flash)
- currentDir[R:]:    128 bytes (current path for RAM)
- Path work buffer:  256 bytes (for normalization)
- Subtotal:          ~512 bytes

Contiguous File Tracking (RAM only):
- Contiguous flag:   Stored in existing block/file metadata (no extra cost)
- Subtotal:          ~0 bytes (metadata reuses file system structures)

File Handles (shared):
- 2 handles × 4KB buffer each = 8KB

Total Hub RAM:        ~33KB (fits in 512KB hub RAM)
```

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Hub RAM exhaustion | High | Careful memory budgeting, consider reducing MAX_FILES_OPEN |
| PSRAM initialization conflict | Medium | Ensure single PSRAM driver instance |
| API complexity | Medium | Keep backward compatibility, minimal changes |
| Performance regression | Low | RAM will be faster, Flash unchanged |

---

## Success Criteria

1. **Backward Compatible**: Existing code using flash_fs.spin2 works with F: or no prefix
2. **Unified API**: Same open/read/write/close calls for both devices
3. **RAM Simplicity**: No unnecessary wear-leveling overhead for RAM
4. **Full Test Coverage**: All existing tests pass + new RAM tests
5. **Documentation**: Clear guide for using dual-device system

---

## Current Directory Support Analysis

### Finding: Existing Flash FS is FLAT (No Hierarchical Folders)

The current `flash_fs.spin2` implements a **flat file system**:

| Feature | Current Status |
|---------|----------------|
| `directory()` | Iterator only - lists all files sequentially |
| `mkdir()` / `rmdir()` | **NOT IMPLEMENTED** |
| `chdir()` / `getcwd()` | **NOT IMPLEMENTED** |
| Path separators (`/` or `\`) | Not parsed - treated as filename characters |
| Subdirectory traversal | **NOT IMPLEMENTED** |
| Filename max length | 127 characters |

**Current Behavior Example**:
```spin2
' These are just filenames - NOT actual folders:
open("logs/data.txt", "w")      ' Creates file named literally "logs/data.txt"
open("config/settings.dat", "r") ' Looks for file named "config/settings.dat"
```

The `/` character is simply part of the filename string - no folder hierarchy exists.

### Directory Support Options

#### Option A: Keep Flat (Recommended for Initial Release)
- Maintain current behavior
- Simpler implementation
- Lower memory overhead
- Users can use naming conventions: `"log_2024_01.txt"`, `"cfg_network.dat"`
- **Pro**: Faster to implement, matches existing flash_fs behavior
- **Con**: No true folder organization

#### Option B: Add Hierarchical Directories (Future Sprint)
- Add `mkdir(path)`, `rmdir(path)`, `chdir(path)`, `getcwd()`
- Parse path separators in filenames
- Store directory entries as special file types
- Add `opendir()`, `readdir()`, `closedir()` for traversal
- **Pro**: True DOS/Unix-like folder structure
- **Con**: Significant complexity, memory overhead, additional sprint

#### Option C: Virtual Directories (SELECTED APPROACH)
- Storage remains flat (filenames contain full paths like `"logs/2024/data.txt"`)
- Thin API layer parses `/` segments to simulate hierarchy
- `chdir()`, `getcwd()`, `mkdir()`, `rmdir()`, `listdir()` operate on path prefixes
- **Pro**: Appearance of folders with minimal storage overhead
- **Pro**: Backward compatible with existing flat files
- **Con**: Empty directories need marker files or disappear
- **Con**: `listdir()` scans all files (mitigated by prefix filtering)

### Selected Approach: Virtual Directory Simulation

**How It Works**:

```
Underlying Flat Storage:          Simulated Hierarchical View:
─────────────────────────         ──────────────────────────────
"config.dat"                      F:/
"logs/2024/jan.txt"               ├── config.dat
"logs/2024/feb.txt"               ├── logs/
"logs/2023/dec.txt"                   ├── 2024/
"data/sensors/temp.dat"               │   ├── jan.txt
                                      │   └── feb.txt
                                      └── 2023/
                                          └── dec.txt
                                  └── data/
                                      └── sensors/
                                          └── temp.dat
```

**API Behavior**:

| Method | Action |
|--------|--------|
| `chdir("logs/2024")` | Sets `currentDir = "logs/2024/"` |
| `getcwd(p_buf)` | Returns `"logs/2024/"` |
| `open("jan.txt", "r")` | Opens `"logs/2024/jan.txt"` |
| `mkdir("logs/2025")` | Creates marker `"logs/2025/.d"` |
| `rmdir("logs/2023")` | Fails if files have that prefix |
| `listdir(p_path)` | Returns unique next-segments at path |
| `directory()` | Lists files in currentDir only |

**Implementation Notes**:
- `currentDir` stored as 128-byte string per device
- Path resolution handles `.` (current), `..` (parent), absolute paths
- Empty directory markers: `"path/.d"` (hidden 0-byte file)
- `listdir()` extracts unique path segments after prefix

### Recommended Approach (Updated)

**Phase 1 (Sprints 1-6)**: Dual F:/R: with flat storage + virtual directory API
**Phase 2 (If needed)**: True hierarchical directories (Sprint 7 - deferred)

---

## Optional Sprint 7: Hierarchical Directory Support

**Goal**: Add true folder/directory support (if desired)

### Task 7.1: Directory Data Structures
- [ ] Define directory entry block format (special HEAD block type)
- [ ] Add D_DIR state to BlockStates (directory vs file)
- [ ] Design parent/child directory linking

### Task 7.2: Directory Operations
- [ ] Implement `mkdir(p_path)` - create directory
- [ ] Implement `rmdir(p_path)` - remove empty directory
- [ ] Implement `chdir(p_path)` - change working directory
- [ ] Implement `getcwd(p_buffer)` - get current directory

### Task 7.3: Path Parsing
- [ ] Implement path tokenizer (split on `/` or `\`)
- [ ] Handle absolute vs relative paths
- [ ] Handle `.` (current) and `..` (parent) references
- [ ] Update `open()` to resolve paths through directories

### Task 7.4: Directory Enumeration
- [ ] Implement `opendir(p_path)` - open directory for listing
- [ ] Implement `readdir(handle)` - get next entry
- [ ] Implement `closedir(handle)` - close directory handle
- [ ] Update `directory()` to work within current directory

### Task 7.5: Directory Tests
- [ ] Test nested directory creation: `mkdir("a/b/c")`
- [ ] Test file operations in subdirectories
- [ ] Test directory removal constraints (must be empty)
- [ ] Test path resolution edge cases

**Deliverable**: Full hierarchical directory support

**Memory Impact**: ~2-4KB additional for directory tracking structures

---

## Decisions Made

1. **Directory Support**: Virtual directories (Option C) - flat storage with path-parsing API layer
2. **Empty Directories**: Use marker files (`"path/.d"`) to preserve empty directories
3. **Composable Architecture**: dir_fs.spin2 is a standalone wrapper that works with ANY flat FS
4. **Original Unchanged**: flash_fs.spin2 remains completely unmodified
5. **Three Deliverables** (all single-file, self-contained):
   - `flash_fs.spin2` - Original flash driver (UNCHANGED, reference only)
   - `flash_ram_fs.spin2` - New Flash+RAM driver, ONE file containing:
     - SPI Flash PASM driver (embedded, copied from flash_fs)
     - PSRAM PASM driver (embedded, incorporated from HDMI reference)
     - Full F:/R: API with contiguous files and fragmentation management
   - `dir_fs.spin2` - Directory wrapper (works with any FS driver)
6. **Naming Convention** (extensible for future storage types):
   - `flash_fs.spin2` - Flash only (P2 Edge)
   - `flash_ram_fs.spin2` - Flash + PSRAM (P2 Edge 32MB)
   - `flash_sd_fs.spin2` - Flash + microSD (future)
   - `dir_fs.spin2` - Directory wrapper (works with any)
7. **RAM Regression Tests**: Full test suite mirroring flash tests (800+ tests target)
8. **Contiguous Files** (RAM only): Buffers ARE files - just contiguous ones
   - Same naming, same directory listing as regular files
   - Size REQUIRED at creation (fixed, cannot grow)
   - `create_contiguous()`, `get_address()`, `is_contiguous()`
   - `stream_write()`, `stream_read()` for high-speed hardware access
   - **Unified memory pool**: contiguous and regular files share same space
   - `compact()` moves regular file blocks to create contiguous free regions
   - Not applicable to Flash (too slow for hardware streaming)
9. **Fragmentation Management** (RAM contiguous region):
   - `contiguous_status()` - total free, largest block, fragment count, compactable
   - `fragmentation_percent()` - 0-100% fragmentation severity
   - `compact()` - **incremental**: moves ONE file, returns (reclaimed, largest_available)
   - `compact_all()` - convenience: loops compact() until done
   - `compact_needed()` - quick check if compaction would help
   - Incremental approach: predictable timing, can stop when goal met
   - WARNING: `compact()` invalidates cached addresses from `get_address()`
10. **Multi-Cog Safety** (dual-lock pattern):
    - `flashLock` for F: operations, `ramLock` for R: operations
    - Allows F: and R: access in **parallel** from different cogs
    - Per-cog error codes: `errorCode LONG[8]`
    - Cross-device operations acquire both locks
    - Matches flash_fs.spin2 locking pattern
11. **Default Drive**: F: (Flash) when no drive prefix specified - backward compatible
12. **Block Size**: 4KB for both Flash and RAM (simplicity, adjustable later if needed)
13. **Cross-Device Copy**: Built-in `copy_file(src, dst)` helper provided
14. **RAM Persistence Warning**: None - trust the user knows R: is volatile
15. **Super-Root Directory**: When no drive selected, `listdir()` shows F: and R: as top-level entries
    - `chdir("..")` from drive root returns to super-root
    - More discoverable, matches DOS/Windows multi-drive behavior
16. **Circular Files**: Supported on both F: and R: drives
17. **Mount Behavior**: `mount()` initializes both devices together (no independent mounting)
18. **Format Behavior**: Selectable - `format(DRIVE_F)`, `format(DRIVE_R)`, or `format(DRIVE_BOTH)`
19. **File Handle Pool**: Unified pool shared between F: and R:
    - Each handle has 1-bit device flag
    - More flexible resource utilization
    - Simpler API
20. **PSRAM Driver**: Simplified - remove per-cog command interface
    - File system locks serialize access anyway
    - Runs inline in calling cog (like Flash driver)
    - Less complexity, lower overhead
21. **PSRAM Transfer Mode**: Block-based (Option A)
    - 4KB blocks with command/address per block
    - Simpler, consistent with Flash model
    - ~1-2% overhead vs streaming mode - acceptable for most use cases
    - See `TECHNICAL_DEBT.md` TD-001 for potential streaming optimization
