ENTRY(Reset_Handler)

/* Arduino Due (ATSAM3X8E)
   FLASH total: 512 KB @ 0x00080000 .. 0x000FFFFF

   ✅ Reserva 1 página (256 bytes) NO FIM da FLASH para persistência:
      NVM (Flash page): 0x000FFF00 .. 0x000FFFFF

   SRAM : 96 KB @ 0x20070000
*/

MEMORY
{
  /* FLASH "do firmware": termina antes da última página */
  FLASH (rx)  : ORIGIN = 0x00080000, LENGTH = 512K - 256

  /* Última página da flash reservada para storage */
  NVM   (rx)  : ORIGIN = 0x000FFF00, LENGTH = 256

  RAM   (rwx) : ORIGIN = 0x20070000, LENGTH = 96K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
  /* Vector table goes first in flash */
  .isr_vector :
  {
    KEEP(*(.isr_vector))
  } > FLASH

  /* Code + read-only data */
  .text :
  {
    *(.text*)
    *(.rodata*)
    *(.glue_7)
    *(.glue_7t)
    *(.eh_frame*)
    KEEP(*(.init))
    KEEP(*(.fini))
  } > FLASH

  /* Exception unwind tables (GCC may emit) */
  .ARM.exidx :
  {
    __exidx_start = .;
    *(.ARM.exidx*)
    __exidx_end = .;
  } > FLASH

  /* Swift extra sections (keep them in FLASH if present) */
  .swift_modhash     : { *(.swift_modhash*)     } > FLASH
  .swift_reflstr     : { *(.swift_reflstr*)     } > FLASH
  .swift_reflstr16   : { *(.swift_reflstr16*)   } > FLASH
  .swift_reflstr32   : { *(.swift_reflstr32*)   } > FLASH
  .swift5_types      : { *(.swift5_types*)      } > FLASH
  .swift5_proto      : { *(.swift5_proto*)      } > FLASH
  .swift5_protos     : { *(.swift5_protos*)     } > FLASH
  .swift5_protocols  : { *(.swift5_protocols*)  } > FLASH
  .swift5_fieldmd    : { *(.swift5_fieldmd*)    } > FLASH
  .swift5_assocty    : { *(.swift5_assocty*)    } > FLASH
  .swift5_replace    : { *(.swift5_replace*)    } > FLASH
  .swift5_replac2    : { *(.swift5_replac2*)    } > FLASH
  .swift5_capture    : { *(.swift5_capture*)    } > FLASH
  .swift5_builtin    : { *(.swift5_builtin*)    } > FLASH
  .swift5_mpenum     : { *(.swift5_mpenum*)     } > FLASH

  /* --- IMPORTANT: set flash end AFTER all flash sections --- */
  . = ALIGN(4);
  __flash_end = .;
  _etext = __flash_end;

  /* Safety: firmware não pode invadir a NVM reservada */
  ASSERT(__flash_end <= ORIGIN(FLASH) + LENGTH(FLASH), "FLASH overflow: firmware invadiu a area NVM reservada!")

  /* Start of init values for .data (in FLASH) */
  _sidata = __flash_end;

  /* Initialized data -> in RAM, load image placed in FLASH at __flash_end */
  .data : AT ( __flash_end )
  {
    . = ALIGN(4);
    _sdata = .;
    *(.data*)
    *(.data.*)
    . = ALIGN(4);
    _edata = .;
  } > RAM

  /* Uninitialized data */
  .bss :
  {
    . = ALIGN(4);
    _sbss = .;
    *(.bss*)
    *(.bss.*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
  } > RAM

  /* Heap start symbol for support.c allocator (uses _end) */
  . = ALIGN(8);
  _end = .;
  PROVIDE(end = .);

  /* ✅ Reserva explícita da página de NVM
     - NOLOAD: não grava bytes no bin (fica "livre"), mas a área fica reservada no link.
     - Você vai programar/gravar nela em runtime via EEFC.
  */
  .nv_storage (NOLOAD) :
  {
    __nv_start = .;
    . = ORIGIN(NVM) + LENGTH(NVM); /* força ocupar toda a região */
    __nv_end = .;
  } > NVM

  /DISCARD/ :
  {
    *(.comment*)
    *(.note*)
  }
}