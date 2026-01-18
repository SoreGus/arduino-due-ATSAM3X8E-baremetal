# ATSAM3X8E Bare Metal (Arduino Due)

Bare metal firmware project for the **ATSAM3X8E** microcontroller (ARM Cortex-M3),
used on the **Arduino Due** board.

This repository contains a minimal and fully standalone setup:
no Arduino core, no CMSIS, no HAL — only the ARM GNU toolchain,
a custom linker script, startup code, and a simple build/upload flow.

## Target MCU

- MCU: ATSAM3X8E  
- Architecture: ARM Cortex-M3 (ARMv7-M)  
- Max clock: 84 MHz  
- Flash: 512 KB  
- SRAM: 96 KB  
- Boot ROM: SAM-BA  

## Requirements

### Toolchain
- arm-none-eabi-gcc
- arm-none-eabi-objcopy
- make

### Uploader
- bossac (from BOSSA)

#### macOS
``` bash
brew install bossa
brew install –cask gcc-arm-embedded
```

#### Linux (Debian/Ubuntu)
``` bash
sudo apt install gcc-arm-none-eabi binutils-arm-none-eabi bossac
```

## Build
This generates:

- firmware.elf  
- firmware.bin  
- firmware.map  

## Upload (Arduino Due)

Use the **Programming Port** (not the Native USB port).
``` bash
./run.sh
```

The script will:

1. Build the firmware  
2. Detect the serial port automatically  
3. Trigger the 1200 bps bootloader reset  
4. Upload the binary using bossac  

## Notes

- This project runs fully bare metal (no runtime, no standard library).
- All interrupt vectors and memory initialization are handled manually.
- Intended for learning, experimentation, and as a clean base for custom firmware.

## License

MIT