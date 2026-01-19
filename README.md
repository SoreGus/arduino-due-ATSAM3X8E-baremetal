# ATSAM3X8E Bare Metal (Arduino Due) — Embedded Swift

Bare‑metal firmware project for the **ATSAM3X8E** microcontroller (ARM Cortex‑M3),
used on the **Arduino Due** board, written in **Embedded Swift**.

This repository demonstrates that **Swift can be used as a systems / embedded language**,
compiling directly to ARM machine code and running **without an OS, without Arduino Core,
without CMSIS, and without any HAL**.

What’s included:
- custom linker script (`linker.ld`)
- custom startup + vector table (`startup.s`)
- a minimal C support layer (`support.c`)
- Swift compiled in **Embedded Swift** mode
- final link with **ARM GNU** toolchain
- flashing via **BOSSA** (`bossac`) using the Due bootloader
- **real 84 MHz clock init** (PLLA → MCK)
- **SysTick 1 ms timer** with **deadline‑based scheduling (no drift)**
- **UART serial output** via the Arduino Due **Programming Port**

---

## Target MCU

- MCU: **ATSAM3X8E**
- Architecture: **ARM Cortex‑M3 (ARMv7‑M)**
- Max clock: **84 MHz**
- Flash: **512 KB**
- SRAM: **96 KB**
- Boot ROM: **SAM‑BA**
- Board: **Arduino Due**
- LED example: **PB27 (Arduino pin D13 / LED “L”)**

---

## What “Embedded Swift” Means Here

This project uses Swift as a **language frontend** in a freestanding environment.

✅ Swift compiles to ARM object code (`.o`)  
✅ Code runs **bare metal**  
✅ No OS  
✅ No Arduino framework  
✅ No CMSIS / HAL  
✅ No Foundation  
✅ No libc required  

The entry point is a C‑ABI symbol exported from Swift:

```swift
@_cdecl("main")
public func main() -> Never
```

`startup.s` calls `main()` after:
- copying `.data` from Flash → RAM
- zeroing `.bss`
- setting `SCB->VTOR` to the local vector table
- enabling interrupts

---

## Repository Layout

- `main.swift`  
  Blink + UART example using **PIOB PB27** and a **deadline‑aligned 1 s loop** (no drift).

- `Timer.swift`  
  SysTick configured for **1 ms tick**, plus helpers used for absolute‑time scheduling.

- `Clock.swift`  
  Initializes **84 MHz** by enabling the crystal oscillator, configuring **PLLA**, and
  switching **MCK** to PLLA. Uses timeouts to avoid silent hangs.

- `SerialUART.swift`  
  Minimal UART driver for the **Programming Port** (no printf, no division, no heap).
  Supports byte output and HEX printing without pulling heavy runtime symbols.

- `MMIO.swift`  
  Low‑level MMIO helpers and small barrier/IRQ functions exposed from `support.c`.

- `startup.s`  
  Vector table + Reset handler. Installs VTOR and wires SysTick to `SysTick_Handler`.

- `linker.ld`  
  Memory map for ATSAM3X8E (Flash @ `0x00080000`, SRAM @ `0x20070000`) and required
  symbols for startup + minimal runtime.

- `support.c`  
  Minimal functions required by Embedded Swift (stack guard, allocator stub, memclr,
  small PRNG), plus CPU helpers (`nop`, `cpsie/cpsid`, `dsb/isb`) and **volatile MMIO**
  implementations.

- `Makefile`  
  Builds: `startup.o`, `support.o`, Swift module → `swift.o`, links → `firmware.elf`,
  converts → `firmware.bin`.

- `run.sh`  
  Builds and uploads the firmware using `bossac`. Always overwrites `last_run.log`
  and prints colored status lines.

- `serial.sh`  
  Opens a serial console automatically using **picocom** (preferred) or **screen**,
  with auto‑port detection.

---

## Requirements

### Toolchain (build/link)
- `arm-none-eabi-gcc`
- `arm-none-eabi-objcopy`
- `make`

### Embedded Swift Toolchain
You need a Swift snapshot toolchain that supports **Embedded Swift**.
Recommended via **swiftly**.

### Uploader
- `bossac` (BOSSA)

### Serial Monitor (recommended)
- `picocom` (preferred)
- fallback: `screen`

---

## Installation

### macOS

```bash
brew install make bossa picocom
brew install --cask gcc-arm-embedded
brew install swiftly

swiftly init
swiftly install main-snapshot
swiftly use main-snapshot
```

Open a new shell and confirm:

```bash
swiftc --version
```

### Linux (Debian / Ubuntu)

```bash
sudo apt update
sudo apt install -y   build-essential   gcc-arm-none-eabi   binutils-arm-none-eabi   bossac   picocom
```

Install swiftly and a snapshot toolchain according to:
https://github.com/apple/swiftly

---

## Build Outputs

Running the build produces:

- `firmware.elf` — linked ELF file
- `firmware.bin` — raw binary for flashing
- `firmware.map` — linker map
- `last_run.log` — last run log (overwritten each run)

Clean:

```bash
make clean
```

---

## Upload (Arduino Due)

⚠️ Use the **Programming Port**, not the Native USB port.

```bash
./run.sh
```

The script will:
1. verify required tools
2. compile Swift + assembly
3. link using ARM GNU tools
4. upload the firmware using `bossac`

---

## Serial Console

After flashing:

```bash
./serial.sh
```

This opens a serial monitor at **115200 baud** with auto‑detected port.
Exit `picocom` with **Ctrl+A, Ctrl+X**.

---

## Example Output

```
BOOT
clock_ok=1
tick=0x000003E8
tick=0x000007D0
tick=0x00000BB8
...
```

Ticks increment **exactly by 1000 ms**, demonstrating:
- correct 84 MHz clock
- correct SysTick configuration
- deadline‑based scheduling without drift

---

## Clock + Timer Notes (Important)

### Real 84 MHz clock (no “fake delays”)
`Clock.swift` configures:
- crystal oscillator (MAINCK)
- **PLLA** to 84 MHz (12 MHz × (MULA+1) / DIVA)
- switches **MCK** to PLLA and waits for `MCKRDY`

SysTick uses `CLKSRC = CPU clock`, so:

```swift
reload = cpuHz / 1000 - 1
```

produces a **true 1 ms tick**.

### Deadline‑based timing (no drift)
Periodic tasks are scheduled using **absolute deadlines**, not chained delays.
This avoids cumulative error caused by serial I/O or other work inside the loop.

### Volatile MMIO
Polling registers requires volatile access. This repo provides
`bm_read32` / `bm_write32` in `support.c` and routes Swift MMIO through them
to prevent incorrect compiler optimizations.

---

## Troubleshooting

- **No serial output**
  - Ensure you are connected to the **Programming Port**.
  - Close any other serial monitor before opening `serial.sh`.

- **LED stays ON or OFF**
  - Confirm PB27 clock is enabled (`PMC_PCER0`).
  - Confirm `startup.s` installs VTOR correctly.

- **Timing drift**
  - Ensure you are using deadline‑based scheduling, not `sleep(ms:)` in a loop.

---

## License

MIT
