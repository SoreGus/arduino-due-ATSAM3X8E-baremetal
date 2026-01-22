# ATSAM3X8E Bare Metal (Arduino Due) — Embedded Swift

Bare‑metal firmware project for the **ATSAM3X8E** microcontroller (ARM Cortex‑M3),
used on the **Arduino Due** board, written in **Embedded Swift**.

This repository demonstrates that **Swift can be used as a systems / embedded language**,
compiling directly to ARM machine code and running **without an OS, without Arduino Core,
without CMSIS, and without any HAL**.

---

## What’s Included

- Custom linker script (`linker.ld`)
- Custom startup + vector table (`startup.s`)
- Minimal C support layer (`support.c`)
- Swift compiled in **Embedded Swift** mode
- Final link with **ARM GNU** toolchain
- Flashing via **BOSSA** (`bossac`) using the Due bootloader
- **84 MHz real clock initialization** (PLLA → MCK)
- **SysTick 1 ms timer** with deadline‑based scheduling (no drift)
- **UART serial output** via the Arduino Due Programming Port
- **I2C (TWI) driver written from scratch**, supporting:
  - Master mode
  - Slave mode
  - Polling‑based operation (no interrupts)
  - Compatibility with Arduino `Wire` protocol
  - Tested against **Arduino Giga** as I2C Master
- **Persistent Flash Key/Value storage** using the SAM3X8E **EEFC** controller

---

## Target MCU

- MCU: **ATSAM3X8E**
- Architecture: **ARM Cortex‑M3 (ARMv7‑M)**
- Max clock: **84 MHz**
- Flash: **512 KB (internal)**
- SRAM: **96 KB**
- Boot ROM: **SAM‑BA**
- Board: **Arduino Due**
- I2C Pins (Wire):
  - SDA: **PB12** (Arduino pin 20)
  - SCL: **PB13** (Arduino pin 21)

---

## Embedded Swift Explained

This project uses Swift as a **freestanding language frontend**.

- No OS
- No Arduino framework
- No CMSIS
- No HAL
- No Foundation
- No libc

Swift is compiled to ARM object files and linked like C.

The entry point is:

```swift
@_cdecl("main")
public func main() -> Never
```

The startup code performs:
- `.data` copy (Flash → RAM)
- `.bss` zero
- VTOR setup
- SysTick configuration
- Jump to `main()`

---

## EEFC and Flash Persistence (Important)

The **EEFC (Enhanced Embedded Flash Controller)** is **not a memory type**.
It is the peripheral responsible for controlling the **internal Flash memory** of the ATSAM3X8E.

Key points:

- EEFC controls the **same internal Flash** used for:
  - Firmware code
  - Constants
  - Persistent data
- There is **no EEPROM** in the ATSAM3X8E.
- Persistent storage is implemented by **reserving a Flash page** and writing to it via EEFC.
- **Re‑flashing firmware erases the entire Flash**, including any stored data.

> ⚠️ This means:
> Even if you upload the *same firmware binary*, all EEFC‑stored values are lost.

### Flash Banks

- Flash is split into two banks:
  - **Bank 0** → controlled by **EEFC0**
  - **Bank 1** → controlled by **EEFC1**
- This project stores data in **Bank 1** to reduce risk while executing code from Bank 0.

### EEFC Storage Layer

This repository includes a **defensive, UserDefaults‑like key/value storage layer**:

- Single reserved Flash page
- CRC‑protected
- Versioned format
- String‑based keys
- Supported types:
  - `String`
  - `U32`
  - `Bool`
  - Raw bytes
- Explicit error reporting with human‑readable messages

This is meant for **configuration, counters, calibration values**, not frequent writes.

---

## I2C (TWI) Implementation

This project contains a **fully custom I2C (TWI) implementation** written directly
against the ATSAM3X8E registers.

### Design Goals

- Arduino `Wire`‑like API
- Support **Master and Slave**
- **Polling‑based**, no interrupts
- Deterministic timing (safe for Embedded Swift)
- No DMA / PDC usage
- No dependencies on ArduinoCore‑sam

### Supported Features

- `begin()` — master mode
- `begin(address)` — slave mode
- `onReceive {}` callback (slave)
- `onRequest {}` callback (slave)
- `beginTransmission()` / `write()` / `endTransmission()`
- `requestFrom()` / `available()` / `read()`

### Slave Design (Important)

- The slave is **polling‑based**
- `i2c.poll()` **must be called continuously**
- **Do not print inside callbacks**
- Callbacks only update state
- UART output happens in the main loop

This avoids timing violations and missed `TXRDY / RXRDY` windows.

### Tested Setup

- **Arduino Due**: I2C Slave (this project)
- **Arduino Giga**: I2C Master (Arduino `Wire` library)
- Speed: 100 kHz and 50 kHz tested
- Address: `0x42` (7‑bit)

Data exchange verified in both directions.

---

## Repository Layout

- `main.swift` — Example firmware
- `EEFC.swift` — Flash key/value persistence layer
- `I2C.swift` — Full TWI driver
- `Timer.swift` — SysTick driver
- `Clock.swift` — 84 MHz clock init
- `SerialUART.swift` — UART driver
- `MMIO.swift` — Volatile MMIO helpers
- `startup.s` — Vector table + reset handler
- `linker.ld` — Memory map
- `support.c` — Minimal C runtime glue
- `Makefile` — Build pipeline
- `run.sh` — Build + flash
- `serial.sh` — Serial monitor

---

## Build

```bash
make
```

Clean:

```bash
make clean
```

---

## Flash (Arduino Due)

⚠️ Use the **Programming Port**.

```bash
./run.sh
```

---

## Serial Monitor

```bash
./serial.sh
```

---

## License

MIT
