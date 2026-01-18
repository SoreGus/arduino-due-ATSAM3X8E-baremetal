ENTRY(Reset_Handler)

/* Arduino Due (SAM3X8E):
   Flash: 512 KB at 0x00080000
   SRAM:  96 KB at 0x20070000 (SAM3X has SRAM0+SRAM1 contiguous in that region)
*/

MEMORY
{
  FLASH (rx)  : ORIGIN = 0x00080000, LENGTH = 512K
  RAM   (rwx) : ORIGIN = 0x20070000, LENGTH = 96K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
  .isr_vector :
  {
    KEEP(*(.isr_vector))
  } > FLASH

  .text :
  {
    *(.text*)
    *(.rodata*)
    _etext = .;
  } > FLASH

  _sidata = LOADADDR(.data);

  .data : AT ( _etext )
  {
    _sdata = .;
    *(.data*)
    _edata = .;
  } > RAM

  .bss :
  {
    _sbss = .;
    *(.bss*)
    *(COMMON)
    _ebss = .;
  } > RAM
}