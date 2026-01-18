.syntax unified
.cpu cortex-m3
.thumb

.global Reset_Handler
.global Default_Handler
.extern main

/* Linker symbols */
.extern _estack
.extern _sidata
.extern _sdata
.extern _edata
.extern _sbss
.extern _ebss

/* ---------------- Vector table ---------------- */
.section .isr_vector, "a", %progbits
.global g_pfnVectors
.type g_pfnVectors, %object
g_pfnVectors:
  .word _estack
  .word Reset_Handler
  .word Default_Handler /* NMI */
  .word Default_Handler /* HardFault */
  .word Default_Handler /* MemManage */
  .word Default_Handler /* BusFault */
  .word Default_Handler /* UsageFault */
  .word 0
  .word 0
  .word 0
  .word 0
  .word Default_Handler /* SVC */
  .word Default_Handler /* DebugMon */
  .word 0
  .word Default_Handler /* PendSV */
  .word Default_Handler /* SysTick */

  /* External IRQs: keep a bunch default */
  .rept 64
    .word Default_Handler
  .endr

.size g_pfnVectors, . - g_pfnVectors

/* ---------------- Reset Handler ---------------- */
.section .text.Reset_Handler, "ax", %progbits
.thumb_func
.type Reset_Handler, %function
Reset_Handler:
  /* Copy .data from Flash to RAM */
  ldr r0, =_sidata
  ldr r1, =_sdata
  ldr r2, =_edata
1:
  cmp r1, r2
  bcs 2f
  ldr r3, [r0], #4
  str r3, [r1], #4
  b   1b

2:
  /* Zero .bss */
  ldr r1, =_sbss
  ldr r2, =_ebss
  movs r3, #0
3:
  cmp r1, r2
  bcs 4f
  str r3, [r1], #4
  b   3b

4:
  bl  main

5:
  b   5b

/* ---------------- Default Handler ---------------- */
.section .text.Default_Handler, "ax", %progbits
.thumb_func
.type Default_Handler, %function
Default_Handler:
  b Default_Handler
  