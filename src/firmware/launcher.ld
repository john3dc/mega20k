OUTPUT_ARCH(m68k)
ENTRY(_start)
MEMORY { ROM (rx) : ORIGIN = 0, LENGTH = 64K
         RAM (rw) : ORIGIN = 0xff0000, LENGTH = 60K }
SECTIONS {
 .vectors : { KEEP(*(.vectors)) } > ROM
 .text : { *(.text.start) *(.text*) *(.rodata*) } > ROM
 .data : { __data_start = .; *(.data*) __data_end = .; } > RAM AT> ROM
 __data_load = LOADADDR(.data);
 .bss (NOLOAD) : { __bss_start = .; *(.bss*) *(COMMON) __bss_end = .; } > RAM
 /DISCARD/ : { *(.comment) *(.eh_frame*) }
 ASSERT(__bss_end < 0xffd000, "Leave at least 12 KiB for the stack")
}
