/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef NANO_CORE_FORMAT_H
#define NANO_CORE_FORMAT_H
#include <stdint.h>
#include <stddef.h>
#define CORE_HEADER_BYTES 512u
#define CORE_SLOT_ADDRESS 0x100000UL
#define CORE_SLOT_BYTES 0x100000UL
#define CORE_AUTOBOOT_RETURN 1u
typedef struct { uint32_t bytes,crc,next,address; char id[32],title[64]; uint32_t flags; } CoreInfo;
uint32_t core_crc32(uint32_t crc,const uint8_t *data,size_t bytes);
int core_header(const uint8_t *header,uint32_t file_bytes,CoreInfo *info);
int core_payload(const uint8_t *data,const CoreInfo *info);
#endif
