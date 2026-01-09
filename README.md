# P2 Dual Flash/RAM File System

A unified file system driver for the Parallax Propeller 2 (P2-EC32MB module) that provides seamless access to both Flash and PSRAM storage.

## Overview

This project creates a dual-device file system supporting:

| Drive | Storage | Size | Persistence | Use Case |
|-------|---------|------|-------------|----------|
| **F:** | SPI Flash | 16MB | Persistent | Config, logs, permanent data |
| **R:** | PSRAM | 32MB | Volatile | Temp files, buffers, working data |

## Target Hardware

**P2-EC32MB Module** (Part# 64000-ES)

| Component | Chip | Size | Interface |
|-----------|------|------|-----------|
| Flash | W25Q128JVSIM (Winbond) | 16MB | SPI (P58-P61) |
| PSRAM | APS6404L-3SQR-ZR (AP Memory) | 32MB (4 x 8MB) | QSPI (P40-P57) |
| MCU | P2X8C4M64P | 512KB Hub RAM | - |

## Architecture

```
                     User Application
                           |
              +------------+------------+
              |                         |
       dir_fs.spin2              (direct access)
    [Optional Wrapper]                  |
              |                         |
              +------------+------------+
                           |
                  flash_ram_fs.spin2
                 [Unified F:/R: API]
                           |
              +------------+------------+
              |                         |
         SPI Flash                   PSRAM
        (pins 58-61)              (pins 40-57)
```

## Deliverables

| File | Description | Status |
|------|-------------|--------|
| `flash_ram_fs.spin2` | Dual-device driver (F: + R:) | Planned |
| `dir_fs.spin2` | Optional directory wrapper | Planned |

## Key Features

### Dual-Device Access
```spin2
fs.open("F:config.dat", "r")    ' Read from Flash
fs.open("R:temp.dat", "w")      ' Write to RAM
fs.open("data.txt", "r")        ' Default: Flash (backward compatible)
```

### Contiguous Files (RAM only)
Hardware-accelerated buffers for PWM, DMA, and video:
```spin2
fs.create_contiguous("R:VIDEO", 640*480*4)  ' Allocate 1.2MB contiguous
addr := fs.get_address("R:VIDEO")            ' Get raw PSRAM address
fs.stream_write(addr, @framebuffer, size)    ' High-speed streaming
```

### Virtual Directories
Path-based organization on flat storage:
```spin2
dir.mkdir("logs/2024")
dir.chdir("logs/2024")
handle := dir.open("data.txt", "w")   ' Creates "logs/2024/data.txt"
```

### Multi-Cog Safe
Dual-lock architecture allows parallel F: and R: access from different cogs.

## Project Structure

```
P2-Dual-FLASH-RAM-FS/
├── README.md                 # This file
├── DOCs/
│   └── SPRINT_PLAN.md        # Detailed implementation plan
├── src/                      # Source files (planned)
│   ├── flash_ram_fs.spin2    # Main dual-device driver
│   └── dir_fs.spin2          # Directory wrapper
├── tests/                    # Regression tests (planned)
└── REFERENCE/                # Reference implementations
    ├── FLASH-FS/             # Original flash_fs.spin2
    └── HDMI/                 # PSRAM driver reference
```

## Development Status

**Phase**: Planning Complete

See [DOCs/SPRINT_PLAN.md](DOCs/SPRINT_PLAN.md) for the detailed 7-sprint implementation plan.

## Design Principles

1. **Single-File Design**: Each driver is self-contained (no external dependencies)
2. **Backward Compatible**: No drive prefix defaults to F: (Flash)
3. **Composable**: dir_fs.spin2 works with flash_fs.spin2 OR flash_ram_fs.spin2
4. **Original Unchanged**: flash_fs.spin2 remains unmodified

## License

TBD

## Author

Iron Sheep Productions, LLC
