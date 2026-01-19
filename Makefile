# Makefile — Arduino Due (ATSAM3X8E / Cortex-M3) — Swift Bare Metal (Embedded Swift)
# Layout:
#   src/   -> .swift + .c
#   arm/   -> startup.s + linker.ld
#   build/ -> all build artifacts (.o .elf .bin .map .log)

TARGET      := firmware
CPU         := cortex-m3

CC          := arm-none-eabi-gcc
OBJCOPY     := arm-none-eabi-objcopy

# Overridable by run.sh
SWIFTC             ?= swiftc
SWIFT_RESOURCE_DIR ?=
SWIFT_TARGET       ?= armv7-none-none-eabi

BUILD_DIR ?= build
SRC_DIR   ?= src
ARM_DIR   ?= arm

ARCH_C  := -mcpu=$(CPU) -mthumb

# Keep enums consistent across C objs (fixes "variable-size enums" warning)
CFLAGS  := $(ARCH_C) -O2 -ffreestanding -fno-builtin -Wall -Wextra \
           -fno-short-enums \
           -nostdlib -nostartfiles

LDFLAGS := $(ARCH_C) -T $(ARM_DIR)/linker.ld \
          -Wl,-Map=$(BUILD_DIR)/$(TARGET).map -Wl,--gc-sections -nostdlib

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
SWIFT_SRCS := $(SRC_DIR)/MMIO.swift \
              $(SRC_DIR)/Clock.swift \
              $(SRC_DIR)/Timer.swift \
              $(SRC_DIR)/main.swift \
              $(SRC_DIR)/ATSAM3X8E.swift

STARTUP_S  := $(ARM_DIR)/startup.s
LINKER_LD  := $(ARM_DIR)/linker.ld

STARTUP_O  := $(BUILD_DIR)/startup.o
SUPPORT_O  := $(BUILD_DIR)/support.o
SWIFT_O    := $(BUILD_DIR)/swift.o

ELF := $(BUILD_DIR)/$(TARGET).elf
BIN := $(BUILD_DIR)/$(TARGET).bin
MAP := $(BUILD_DIR)/$(TARGET).map

all: $(BIN)

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(STARTUP_O): $(STARTUP_S) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(SUPPORT_O): $(SRC_DIR)/support.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

# Compile ALL Swift sources together into ONE object (single Swift module)
$(SWIFT_O): $(SWIFT_SRCS) | $(BUILD_DIR)
	$(SWIFTC) $(SWIFTFLAGS) $(SWIFT_SRCS) -o $@

$(ELF): $(STARTUP_O) $(SUPPORT_O) $(SWIFT_O) $(LINKER_LD) | $(BUILD_DIR)
	$(CC) $(STARTUP_O) $(SUPPORT_O) $(SWIFT_O) $(LDFLAGS) -o $@

$(BIN): $(ELF) | $(BUILD_DIR)
	$(OBJCOPY) -O binary $< $@

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean