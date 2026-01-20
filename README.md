
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

---

## Target MCU

- MCU: **ATSAM3X8E**
- Architecture: **ARM Cortex‑M3 (ARMv7‑M)**
- Max clock: **84 MHz**
- Flash: **512 KB**
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

- `main.swift`  
  Example firmware running the Due as **I2C Slave**, responding to an Arduino Giga Master.

- `I2C.swift`  
  Full TWI driver (Master + Slave), register‑level, polling‑based.

- `Timer.swift`  
  SysTick driver (1 ms tick) with deadline‑aligned scheduling.

- `Clock.swift`  
  84 MHz clock initialization via PLLA.

- `SerialUART.swift`  
  Minimal UART driver for the Programming Port.

- `MMIO.swift`  
  Volatile MMIO helpers bridged from C.

- `startup.s`  
  Vector table + reset handler.

- `linker.ld`  
  Memory map and runtime symbols.

- `support.c`  
  Minimal C runtime glue required by Embedded Swift.

- `Makefile`  
  Full build and link pipeline.

- `run.sh`  
  Build + flash script using `bossac`.

- `serial.sh`  
  Interactive serial monitor with auto‑port detection.

---

## Example I2C Slave Output (Due)

```
DUE I2C SLAVE START
I2C slave init OK
rxCount=1 txCount=2 counter=0x5D
rxCount=2 txCount=4 counter=0x5E
rxCount=3 txCount=6 counter=0x5F
...
```

## Example I2C Master Output (Giga)

```
WRITE -> 1E 2E 3E
READ  <- 3E 3F 40 41
WRITE -> 1F 2F 3F
READ  <- 3F 40 41 42
```

---

## Requirements

### Toolchain
- `arm-none-eabi-gcc`
- `arm-none-eabi-objcopy`
- `make`

### Swift
- Swift snapshot with **Embedded Swift**
- Recommended via **swiftly**

### Upload
- `bossac`

### Serial
- `picocom` (preferred)
- `screen` (fallback)

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
