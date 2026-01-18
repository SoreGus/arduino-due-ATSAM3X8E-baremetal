#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(addr))

// --- SAM3X8E base addresses (peripheral memory map) ---
#define PMC_BASE      0x400E0600u
#define PIOB_BASE     0x400E1000u

// PMC registers
#define PMC_PCER0     REG32(PMC_BASE + 0x0010u)   // Peripheral Clock Enable Register 0

// PIOB registers (PIO controller)
#define PIO_PER       REG32(PIOB_BASE + 0x0000u)  // PIO Enable Register
#define PIO_OER       REG32(PIOB_BASE + 0x0010u)  // Output Enable Register
#define PIO_SODR      REG32(PIOB_BASE + 0x0030u)  // Set Output Data Register
#define PIO_CODR      REG32(PIOB_BASE + 0x0034u)  // Clear Output Data Register

// Due LED "L" is on PB27 (Arduino Due)
#define LED_PIN       27u
#define LED_MASK      (1u << LED_PIN)

// Peripheral ID for PIOB on SAM3X (commonly ID=13). If you want, we can confirm by datasheet.
#define ID_PIOB       13u

static void delay(volatile uint32_t n) {
    while (n--) {
        __asm__ volatile ("nop");
    }
}

int main(void) {
    // Enable clock for PIOB
    PMC_PCER0 = (1u << ID_PIOB);

    // Enable PIO control on PB27 and set as output
    PIO_PER = LED_MASK;
    PIO_OER = LED_MASK;

    while (1) {
        // LED on (PB27 high)
        PIO_SODR = LED_MASK;
        delay(200000);

        // LED off
        PIO_CODR = LED_MASK;
        delay(200000);
    }
}