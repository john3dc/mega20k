/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "platform.h"
#include "core_loader.h"
#include "core_flash.h"
#include <string.h>
static uint8_t header_buffer[CORE_HEADER_BYTES] __attribute__((aligned(2)));
uint8_t core_flash_transfer(uint8_t value) { IO(0)=value;return IO(0); }
void core_flash_read(uint8_t *data,unsigned bytes) {
 uintptr_t address=(uintptr_t)data;
 // The existing SPI DMA uses the selected device, including flash. Its
 // 512-byte destination must fit an aligned window of 68000 work RAM.
 if(bytes==512 && !(address&1) && (address>>16)==0xff && (address&0xffff)<=0xfe00) {
  IO(22)=0x7f;IO(20)=(uint16_t)address;
  // DMA completes before the MMIO write returns. Make its RAM writes visible
  // to the compiler as well, including when this function is inlined by LTO.
  __asm__ volatile("" ::: "memory");
 } else while(bytes--)*data++=core_flash_transfer(255);
}
void core_flash_select(int selected) { IO(26)=!selected; }
uint16_t core_flash_ticks(void) { return ticks(); }
int core_read_info(FIL *file,CoreInfo *info) {
 UINT got;return !f_read(file,header_buffer,sizeof(header_buffer),&got) && got==sizeof(header_buffer) &&
  f_size(file)<=CORE_HEADER_BYTES+CORE_SLOT_BYTES && core_header(header_buffer,f_size(file),info);
}
static void core_restart(void);
int core_load(const char *path) {
 FIL file;CoreInfo info;
 core_progress(0);
 if(f_open(&file,path,FA_READ))return 0;
 if(!core_read_info(&file,&info) || info.address!=CORE_SLOT_ADDRESS){f_close(&file);return 0;}
 IO(12)=0;uint8_t *data=(uint8_t*)0x400000;
 for(uint32_t pos=0;pos<info.bytes;) {
  UINT got,n=info.bytes-pos>16384?16384:info.bytes-pos;
  if(f_read(&file,data+pos,n,&got) || got!=n){f_close(&file);return 0;}
  pos+=got;core_progress(pos*25/info.bytes);
 }
 f_close(&file);
 // The entire SD file is now in SDRAM. Card removal cannot interrupt a flash
 // transaction; any card or CRC error above leaves both flash slots untouched.
 if(!core_flash_stage(data,&info)){core_flash_select(0);return 0;}
 if(!core_flash_remember(CORE_BASE_ID,&info))return 0;
 core_progress(100);
 core_restart();return 0;
}
static void core_restart(void) {
 IO(26)=1;IO(2)=1;delay_ms(2);IO(28)=0xc020;
 // Reconfiguration normally removes this CPU immediately. A bounded fallback
 // reports a failed restart rather than hanging forever if the pin is absent.
 delay_ms(1000);
}
int core_autostart(void) {
 /* Let two pad scans settle; SELECT remains available on either port. */
 uint16_t start=ticks();unsigned menu=0;
 do {if(buttons()&SELECT)menu=1;}while((uint16_t)(ticks()-start)<150);
 int state=core_flash_boot(CORE_BASE_ID);
 if(menu || state==2){input_clear();return 1;}
 if(state==1) {
  if(buttons()&SELECT){input_clear();return 1;}
  core_restart();return 1;
 }
 return 0;
}
int core_use_base(void) {
#ifdef MEGADRIVE_ADDON
 return 1; /* A game launch must preserve the neutral loader's selection. */
#else
 return core_flash_remember(CORE_BASE_ID,0);
#endif
}
int core_return_to_base(void) {
 if(!core_flash_request_menu())return 0;
 core_restart();return 0;
}
