# Makefile — Arduino Due (ATSAM3X8E / Cortex-M3) — Swift Bare Metal (Embedded Swift)

TARGET      := firmware
CPU         := cortex-m3

CC          := arm-none-eabi-gcc
OBJCOPY     := arm-none-eabi-objcopy

# Overridable by run.sh
SWIFTC             ?= swiftc
SWIFT_RESOURCE_DIR ?=
SWIFT_TARGET       ?= armv7-none-none-eabi

ARCH_C  := -mcpu=$(CPU) -mthumb

# Keep enums consistent across C objs (fixes "variable-size enums" warning)
CFLAGS  := $(ARCH_C) -O2 -ffreestanding -fno-builtin -Wall -Wextra \
           -fno-short-enums \
           -nostdlib -nostartfiles

LDFLAGS := $(ARCH_C) -T linker.ld -Wl,-Map=$(TARGET).map -Wl,--gc-sections -nostdlib

# Embedded Swift flags:
# - Use armv7-none-none-eabi (toolchain ships Swift.swiftmodule for it)
# - Force Cortex-M3/Thumb via -target-cpu + -Xcc flags
SWIFTFLAGS := -O -wmo -c \
              -parse-as-library \
              -target $(SWIFT_TARGET) \
              -Xfrontend -enable-experimental-feature -Xfrontend Embedded \
              -Xfrontend -target-cpu -Xfrontend $(CPU) \
              -Xcc -mcpu=$(CPU) -Xcc -mthumb \
              -Xcc -fno-short-enums

ifneq ($(strip $(SWIFT_RESOURCE_DIR)),)
SWIFTFLAGS += -resource-dir $(SWIFT_RESOURCE_DIR) -I $(SWIFT_RESOURCE_DIR)/embedded
endif

# ✅ Include Clock.swift (fixes "timer slow" by allowing DueClock.init84MHz)
SWIFT_SRCS := MMIO.swift Clock.swift Timer.swift main.swift

all: $(TARGET).bin

startup.o: startup.s
	$(CC) $(CFLAGS) -c $< -o $@

support.o: support.c
	$(CC) $(CFLAGS) -c $< -o $@

# Compile ALL Swift sources together into ONE object (single Swift module)
swift.o: $(SWIFT_SRCS)
	$(SWIFTC) $(SWIFTFLAGS) $(SWIFT_SRCS) -o $@

$(TARGET).elf: startup.o support.o swift.o
	$(CC) startup.o support.o swift.o $(LDFLAGS) -o $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

clean:
	rm -f *.o *.elf *.bin *.map last_run.log

.PHONY: all clean