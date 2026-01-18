// support.c — minimal C support for Embedded Swift on bare metal

#include <stdint.h>
#include <stddef.h>

void bm_nop(void) {
  __asm__ volatile ("nop");
}

// --- If your Swift runtime pulls these, keep ultra-simple stubs ---
// For a real project, you’ll want a proper allocator / stack protector strategy.

void* malloc(size_t size) { (void)size; return 0; }
void  free(void* p) { (void)p; }

int posix_memalign(void** memptr, size_t alignment, size_t size) {
  (void)alignment; (void)size;
  *memptr = 0;
  return 12; // ENOMEM
}

// Stack protector stubs (if enabled somewhere)
uintptr_t __stack_chk_guard = 0xBAADF00D;
void __stack_chk_fail(void) { while (1) { __asm__ volatile ("nop"); } }

// GCC / ARM helper that may be referenced
void __aeabi_memclr(void* dest, size_t n) {
  uint8_t* d = (uint8_t*)dest;
  while (n--) *d++ = 0;
}