/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef NANO_CORE_FLASH_H
#define NANO_CORE_FLASH_H
#include "core_format.h"
/* Transport boundary also used by the fault-injection test harness. */
uint8_t core_flash_transfer(uint8_t value);
/* Continue the selected flash read stream; consume exactly bytes bytes. */
void core_flash_read(uint8_t *data,unsigned bytes);
void core_flash_select(int selected);
uint16_t core_flash_ticks(void);
void core_progress(unsigned percent);
int core_flash_stage(const uint8_t *data,const CoreInfo *info);
/* Two journal sectors outside both bitstream slots. Never touched by stage(). */
#define CORE_BOOT_ADDRESS 0x200000UL
#define CORE_BOOT_BYTES 8192u
int core_flash_remember(const char *base,const CoreInfo *info);
/* 0: stay in base, 1: verified addon, 2: explicit system-menu request. */
int core_flash_boot(const char *base);
int core_flash_request_menu(void);
#endif
