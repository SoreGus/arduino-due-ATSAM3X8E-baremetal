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

// ✅ Volatile MMIO (evita "read otimizado" que trava wait loops)
__attribute__((used))
uint32_t bm_read32(uint32_t addr) {
  return *(volatile uint32_t*)addr;
}

__attribute__((used))
void bm_write32(uint32_t addr, uint32_t value) {
  *(volatile uint32_t*)addr = value;
}

// -----------------------------------------------------------------------------
// Stack protector (Swift pode exigir isso dependendo de flags/toolchain)
// -----------------------------------------------------------------------------
uintptr_t __stack_chk_guard = 0xBAADF00Du;

__attribute__((noreturn))
void __stack_chk_fail(void) {
  while (1) { __asm__ volatile ("nop"); }
}

// -----------------------------------------------------------------------------
// Tiny heap for posix_memalign (Swift runtime usa isso para algumas alocações)
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// Minimal libc-like memory primitives (NO libc)
// Swift/LLVM pode chamar memset/memcpy/memmove e/ou __aeabi_* diretamente.
// -----------------------------------------------------------------------------

__attribute__((used))
void *memset(void *dest, int c, size_t n) {
  uint8_t *p = (uint8_t*)dest;
  uint8_t v = (uint8_t)c;
  while (n--) *p++ = v;
  return dest;
}

__attribute__((used))
void *memcpy(void *dest, const void *src, size_t n) {
  uint8_t *d = (uint8_t*)dest;
  const uint8_t *s = (const uint8_t*)src;
  while (n--) *d++ = *s++;
  return dest;
}

__attribute__((used))
void *memmove(void *dest, const void *src, size_t n) {
  uint8_t *d = (uint8_t*)dest;
  const uint8_t *s = (const uint8_t*)src;

  if (d == s || n == 0) return dest;

  if (d < s) {
    while (n--) *d++ = *s++;
  } else {
    d += n;
    s += n;
    while (n--) *--d = *--s;
  }
  return dest;
}

// -----------------------------------------------------------------------------
// ARM EABI helpers (críticos para o seu erro atual)
// -----------------------------------------------------------------------------

// Signature used by many compilers:
//   void __aeabi_memset(void *dest, size_t n, int c);
__attribute__((used))
void __aeabi_memset(void *dest, size_t n, int c) {
  (void)memset(dest, c, n);
}

__attribute__((used))
void __aeabi_memset4(void *dest, size_t n, int c) {
  (void)memset(dest, c, n);
}

__attribute__((used))
void __aeabi_memset8(void *dest, size_t n, int c) {
  (void)memset(dest, c, n);
}

// Some toolchains call memclr/memclr4/memclr8
__attribute__((used))
void __aeabi_memclr(void *dest, size_t n) {
  (void)memset(dest, 0, n);
}

__attribute__((used))
void __aeabi_memclr4(void *dest, size_t n) {
  (void)memset(dest, 0, n);
}

__attribute__((used))
void __aeabi_memclr8(void *dest, size_t n) {
  (void)memset(dest, 0, n);
}

// Also common:
//   void __aeabi_memcpy(void *dest, const void *src, size_t n);
__attribute__((used))
void __aeabi_memcpy(void *dest, const void *src, size_t n) {
  (void)memcpy(dest, src, n);
}

__attribute__((used))
void __aeabi_memcpy4(void *dest, const void *src, size_t n) {
  (void)memcpy(dest, src, n);
}

__attribute__((used))
void __aeabi_memcpy8(void *dest, const void *src, size_t n) {
  (void)memcpy(dest, src, n);
}

// -----------------------------------------------------------------------------
// Swift hashing seed wants arc4random_buf. Tiny PRNG (NOT crypto-secure).
// -----------------------------------------------------------------------------
static uint32_t g_rng = 0x12345678u;

static uint32_t xorshift32(void) {
  uint32_t x = g_rng;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  g_rng = x;
  return x;
}

__attribute__((used))
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