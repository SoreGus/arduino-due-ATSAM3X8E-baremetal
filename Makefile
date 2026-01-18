# Makefile — Arduino Due (ATSAM3X8E / Cortex-M3) — Swift Bare Metal (Embedded Swift)

TARGET      := firmware
CPU         := cortex-m3

CC          := arm-none-eabi-gcc
OBJCOPY     := arm-none-eabi-objcopy

# Overridable by run.sh
SWIFTC              ?= swiftc
SWIFT_RESOURCE_DIR  ?=
SWIFT_TARGET        ?= armv7-none-none-eabi

ARCH_C      := -mcpu=$(CPU) -mthumb
CFLAGS      := $(ARCH_C) -O2 -ffreestanding -fno-builtin -Wall -Wextra -nostdlib -nostartfiles
LDFLAGS     := $(ARCH_C) -T linker.ld -Wl,-Map=$(TARGET).map -Wl,--gc-sections -nostdlib

# Embedded Swift flags:
# IMPORTANT:
# - We cannot use thumbv7m-none-none-eabi because this toolchain doesn't ship Swift.swiftmodule for it.
# - Use armv7-none-none-eabi (module exists) AND force Cortex-M3/Thumb via -target-cpu and -Xcc flags.
SWIFTFLAGS  := -O -wmo -c \
               -parse-as-library \
               -target $(SWIFT_TARGET) \
               -Xfrontend -enable-experimental-feature -Xfrontend Embedded \
               -Xfrontend -target-cpu -Xfrontend $(CPU) \
               -Xcc -mcpu=$(CPU) -Xcc -mthumb

ifneq ($(strip $(SWIFT_RESOURCE_DIR)),)
SWIFTFLAGS  += -resource-dir $(SWIFT_RESOURCE_DIR) -I $(SWIFT_RESOURCE_DIR)/embedded
endif

all: $(TARGET).bin

startup.o: startup.s
	$(CC) $(CFLAGS) -c $< -o $@

support.o: support.c
	$(CC) $(CFLAGS) -c $< -o $@

main.o: main.swift
	$(SWIFTC) $(SWIFTFLAGS) $< -o $@

$(TARGET).elf: startup.o main.o support.o
	$(CC) startup.o main.o support.o $(LDFLAGS) -o $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

clean:
	rm -f *.o *.elf *.bin *.map last_run.log

.PHONY: all clean