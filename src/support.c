// support.c — minimal C support for Embedded Swift on bare-metal ATSAM3X8E

#include <stdint.h>
typedef unsigned int size_t;

__attribute__((used))
void bm_nop(void) { __asm__ volatile ("nop"); }

__attribute__((used))
void bm_enable_irq(void) { __asm__ volatile ("cpsie i" ::: "memory"); }

__attribute__((used))
void bm_disable_irq(void) { __asm__ volatile ("cpsid i" ::: "memory"); }

__attribute__((used))
void bm_dsb(void) { __asm__ volatile ("dsb 0xF" ::: "memory"); }

__attribute__((used))
void bm_isb(void) { __asm__ volatile ("isb 0xF" ::: "memory"); }

// ✅ Volatile MMIO (isso evita o "read otimizado" que trava wait loops)
__attribute__((used))
uint32_t bm_read32(uint32_t addr) {
  return *(volatile uint32_t*)addr;
}

__attribute__((used))
void bm_write32(uint32_t addr, uint32_t value) {
  *(volatile uint32_t*)addr = value;
}

uintptr_t __stack_chk_guard = 0xBAADF00Du;

__attribute__((noreturn))
void __stack_chk_fail(void) {
  while (1) { __asm__ volatile ("nop"); }
}

extern uint32_t _end;      // provided by linker.ld
extern uint32_t _estack;   // top of stack (end of RAM)

static uintptr_t g_heap = 0;

static void heap_init_once(void) {
  if (g_heap == 0) g_heap = (uintptr_t)&_end;
}

static uintptr_t align_up(uintptr_t p, uintptr_t a) {
  return (p + (a - 1)) & ~(a - 1);
}

int posix_memalign(void **memptr, size_t alignment, size_t size) {
  heap_init_once();

  if (!memptr) return 22; // EINVAL
  if (alignment < sizeof(void*)) alignment = sizeof(void*);
  if ((alignment & (alignment - 1)) != 0) return 22;

  uintptr_t p = align_up(g_heap, (uintptr_t)alignment);
  uintptr_t newp = p + (uintptr_t)size;

  if (newp >= (uintptr_t)&_estack) {
    *memptr = 0;
    return 12; // ENOMEM
  }

  g_heap = newp;
  *memptr = (void*)p;
  return 0;
}

void free(void *ptr) { (void)ptr; }

void __aeabi_memclr(void *dest, size_t n) {
  uint8_t *p = (uint8_t*)dest;
  while (n--) *p++ = 0;
}

// Swift hashing seed wants arc4random_buf. Provide a tiny PRNG (NOT crypto-secure).
static uint32_t g_rng = 0x12345678u;

static uint32_t xorshift32(void) {
  uint32_t x = g_rng;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  g_rng = x;
  return x;
}

void arc4random_buf(void *buf, size_t n) {
  uint8_t *p = (uint8_t*)buf;
  while (n) {
    uint32_t r = xorshift32();
    for (int i = 0; i < 4 && n; i++) {
      *p++ = (uint8_t)(r & 0xFF);
      r >>= 8;
      n--;
    }
  }
}