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
- **real 84 MHz clock init** (PLLA → MCK) and **SysTick 1ms timer**

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
  Minimal blink example using **PIOB PB27** + **SysTick Timer**.

- `Timer.swift`  
  SysTick configured for **1 ms tick** and a busy‑wait `sleep(ms:)`.

- `Clock.swift`  
  Initializes **84 MHz** by enabling the crystal oscillator, configuring **PLLA**, and
  switching **MCK** to PLLA. Uses timeouts to avoid silent hangs.

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
  Builds + auto‑detects serial port + triggers bootloader (1200 bps touch) + uploads
  using `bossac`. Always overwrites `last_run.log` and prints colored status lines.

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

---

## Installation

### macOS

```bash
brew install make bossa
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
sudo apt install -y \
  build-essential \
  gcc-arm-none-eabi \
  binutils-arm-none-eabi \
  bossac
```

Install swiftly and a snapshot toolchain according to the official repo:
https://github.com/apple/swiftly

---

## Build Outputs

Running the build produces:

- `firmware.elf` — linked ELF file
- `firmware.bin` — raw binary for flashing
- `firmware.map` — linker map (useful for inspection)
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
4. detect the serial port automatically
5. trigger the 1200‑bps bootloader reset
6. upload the firmware using `bossac`

---

## Example Behavior

Default firmware blinks:

- LED: **PB27**
- Board LED: Arduino Due **“L” (D13)**

This confirms:
- Swift code is executing
- MMIO writes are correct
- startup + linker + minimal runtime are working
- SysTick tick + clock config are functional

---

## Clock + Timer Notes (Important)

### Real 84 MHz clock (no “fake delays”)
`Clock.swift` configures:
- crystal oscillator (MAINCK)
- **PLLA** to 84 MHz (12 MHz × (MULA+1) / DIVA)
- switches **MCK** to PLLA and waits for `MCKRDY`

After that, SysTick uses `CLKSRC=CPU clock` so:

```swift
reload = cpuHz / 1000 - 1
```

becomes a real 1 ms tick when `cpuHz = 84_000_000`.

### Volatile MMIO
For robust polling loops (waiting on `PMC_SR` flags, etc.), reads/writes must not be
optimized away. This repo provides `bm_read32/bm_write32` in `support.c` using
`volatile` pointers. `MMIO.swift` should route `read32/write32` through those helpers.

---

## Troubleshooting

- **LED stays ON or OFF forever**
  - Confirm you are flashing via the **Programming Port**.
  - Confirm `startup.s` installs VTOR and that SysTick vector points to
    `SysTick_Handler`.

- **SysTick timing wrong / too slow / too fast**
  - Ensure `Clock.init84MHz()` runs successfully before starting SysTick.
  - Ensure SysTick `CSR_CLKSRC` is set (CPU clock, not CPU/8).

- **Build errors: missing symbols like `bm_enable_irq`**
  - Ensure `MMIO.swift` declares the `_silgen_name` functions, and `support.c`
    defines them with `__attribute__((used))`.

---

## License

MIT
