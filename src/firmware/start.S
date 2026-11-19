/* SPDX-License-Identifier: GPL-3.0-or-later */
.section .vectors,"a"
.long 0x00fffffc
.long _start
.rept 62
.long exception
.endr
.section .text.start,"ax"
.global _start
_start:
    move.w #0x2700,%sr
    lea __data_load,%a0
    lea __data_start,%a1
    lea __data_end,%a2
1:  cmpa.l %a2,%a1
    bcc 2f
    move.b (%a0)+,(%a1)+
    bra 1b
2:  lea __bss_start,%a1
    lea __bss_end,%a2
3:  cmpa.l %a2,%a1
    bcc 4f
    clr.b (%a1)+
    bra 3b
4:  jsr main
exception:
    bra exception
