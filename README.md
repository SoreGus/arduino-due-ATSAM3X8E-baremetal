# ATSAM3X8E Bare Metal (Arduino Due) — Embedded Swift

Bare-metal firmware project for the **ATSAM3X8E** microcontroller (ARM Cortex-M3),
used on the **Arduino Due** board, written in **Embedded Swift**.

This repository demonstrates that **Swift can be used as a systems / embedded
language**, compiling directly to ARM machine code and running **without an OS,
without Arduino core, without CMSIS, and without HAL**.

The project uses:
- a custom linker script
- custom startup code
- a minimal runtime layer
- Swift compiled in *Embedded Swift* mode
- ARM GNU toolchain for final linking
- BOSSA (`bossac`) for flashing via the Arduino Due bootloader

---

## Target MCU

- MCU: **ATSAM3X8E**
- Architecture: **ARM Cortex-M3 (ARMv7-M)**
- Max clock: **84 MHz**
- Flash: **512 KB**
- SRAM: **96 KB**
- Boot ROM: **SAM-BA**
- Board: **Arduino Due**
- LED example: **PB27 (Arduino pin D13 / LED “L”)**

---

## What “Embedded Swift” Means Here

This project uses **Swift as a language frontend only**, not as a full runtime.

✔ Swift is compiled to ARM object files (`.o`)  
✔ Code runs **bare metal**  
✔ No operating system  
✔ No Arduino framework  
✔ No CMSIS / HAL  
✔ No Foundation  
✔ No libc  
✔ No dynamic allocation required  

Swift code is linked exactly like C code and entered from `startup.s`
via a C-ABI symbol:

```swift
@_cdecl("main")
public func main() -> Never
```

This allows Swift to behave like a low-level systems language, similar to C
or Rust, while keeping Swift’s syntax and type safety.

## Requirements

### Toolchain
	•	arm-none-eabi-gcc
	•	arm-none-eabi-objcopy
	•	make

### Embedded Swift Toolchain

A Swift snapshot toolchain with Embedded Swift support is required.

Recommended installation via swiftly.

Uploader
	•	bossac (from BOSSA)

### Installation

#### macOS

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
#### Linux (Debian / Ubuntu)

```bash
sudo apt update
sudo apt install -y \
  build-essential \
  gcc-arm-none-eabi \
  binutils-arm-none-eabi \
  bossac
```
Install swiftly and a snapshot toolchain according to:
https://github.com/apple/swiftly

## Build

Running the build produces:
	•	firmware.elf — linked ELF file
	•	firmware.bin — raw binary for flashing
	•	firmware.map — linker map (useful for inspection)

### Upload (Arduino Due)
⚠️ Use the Programming Port, not the Native USB port.
```bash
./run.sh
```

The script will:
	1.	Verify required tools
	2.	Compile Swift and assembly
	3.	Link everything using the ARM GNU linker
	4.	Detect the serial port automatically
	5.	Trigger the 1200-bps bootloader reset
	6.	Upload the firmware using bossac


## Example Behavior

The default firmware blinks:
	•	LED: PB27
	•	Board LED: Arduino Due “L” (D13)

This confirms:
	•	Swift code is executing
	•	MMIO writes are correct
	•	Startup, linker, and runtime are working

## Notes

	•	This is true bare metal execution.
	•	All memory initialization is manual.
	•	No standard library is assumed.
	•	Swift runtime usage is kept to the absolute minimum.
	•	This repository is intended for:
	    •	learning embedded systems internals
	    •	experimenting with Embedded Swift
	    •	serving as a clean base for custom firmware

## License

MIT
