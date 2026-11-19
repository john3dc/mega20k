/* SPDX-License-Identifier: GPL-3.0-or-later
 * SD SPI mode, multi-block reads, read-only. SD v1/v2, SDHC/SDXC, bounded waits. */
#ifndef NANO_SD_TEST
#include "platform.h"
#endif
#include "ff.h"
#include "diskio.h"
static DSTATUS status=STA_NOINIT;
static uint8_t high_capacity;
static uint16_t control=3; /* bit0 CS_N, bit1 <=400 kHz */
static uint8_t transfer(uint8_t v) {
#ifdef NANO_SD_TEST
 return sd_test_transfer(v);
#else
 IO(0)=v; return IO(0);
#endif
}
static void dma_read(uintptr_t address) {
#ifdef NANO_SD_TEST
 sd_test_dma(address);
#else
 IO(20)=address;
#endif
}
static void deselect(void) { IO(2)=control|1; transfer(255); }
static int ready(unsigned timeout) {
 uint16_t t=ticks(); do { if(transfer(255)==255) return 1; } while((uint16_t)(ticks()-t)<timeout); return 0;
}
static uint8_t command(uint8_t cmd,uint32_t arg) {
 /* CMD12 terminates an active CMD18 stream: keep CS low and do not wait
    for 0xff, which may be file data. Its response starts with a stuff byte. */
 if(cmd!=12) {
  deselect(); IO(2)=control&~1;
  if(!ready(500)) return 255;
 }
 transfer(0x40|cmd); transfer(arg>>24); transfer(arg>>16); transfer(arg>>8); transfer(arg);
 transfer(cmd==0?0x95:cmd==8?0x87:1);
 if(cmd==12) transfer(255);
 for(unsigned i=0;i<10;i++) { uint8_t r=transfer(255); if(!(r&128)) return r; }
 return 255;
}
DSTATUS disk_status(BYTE p) { return p?STA_NOINIT:status; }
DSTATUS disk_initialize(BYTE p) {
 if(p) return STA_NOINIT;
 status=STA_NOINIT; control=3; high_capacity=0; IO(2)=3; delay_ms(20);
 for(unsigned i=0;i<10;i++) transfer(255);
 if(command(0,0)!=1) goto done;
 uint8_t r=command(8,0x1aa), v2=0;
 if(r==1) {
  uint32_t r7=0; for(unsigned i=0;i<4;i++) r7=(r7<<8)|transfer(255);
  if((r7&0xfff)!=0x1aa) goto done;
  v2=1;
 } else if(r!=5) goto done;
 uint16_t t=ticks();
 do {
  if(command(55,0)>1) goto done;
  r=command(41,v2?0x40000000:0);
  if(!r) break;
  if(r!=1) goto done;
  delay_ms(1);
 } while((uint16_t)(ticks()-t)<2000);
 if(r) goto done;
 if(v2) {
  if(command(58,0)) goto done;
  uint8_t ocr=transfer(255); high_capacity=(ocr>>6)&1;
  for(unsigned i=0;i<3;i++) transfer(255);
 }
 if(!high_capacity && command(16,512)) goto done;
 control=1; status=0;
done:
 deselect(); return status;
}
/* Subtraction avoids address wrap and 64-bit arithmetic on RV32/68000. */
static int valid_range(LBA_t sector,UINT count) {
 LBA_t last=high_capacity?0xffffffffUL:0x7fffffUL;
 return count && sector<=last && count-1<=last-sector;
}
DRESULT disk_read(BYTE p,BYTE *buf,LBA_t sector,UINT count) {
 if(p || !valid_range(sector,count)) return RES_PARERR;
 if(status) return RES_NOTRDY;
 uint8_t multi=count>1;
 if(command(multi?18:17,high_capacity?sector:sector*512)) goto error;
 do {
  uint16_t t=ticks(); uint8_t token;
  do { token=transfer(255); if(token!=255) break; } while((uint16_t)(ticks()-t)<300);
  if(token!=254) break;
  uintptr_t address=(uintptr_t)buf;
  if(!(address&1) && (address&0xffff)<=0xfe00 &&
     ((address>>16)==0xff || (address>=0x400000 && address<0x800000))) {
   /* Cartridge aperture follows the selected 4 MiB bank. SPI bytes retain
      their big-endian word order, identical to the previous CPU copy. */
   IO(22)=(address>>16)==0xff?0x7f:((address>>16)&0x3f)|(IO(12)<<6);
   dma_read((uint16_t)address);buf+=512;
  } else for(unsigned i=0;i<512;i++) *buf++=transfer(255);
  transfer(255); transfer(255); /* Consume each block's CRC16. */
 } while(--count);
 if(multi) {
  uint8_t stop=command(12,0);
  if(!ready(500) || stop) goto error; /* CMD12 is R1b. */
 }
 if(count) goto error; /* A missing/error token left unread sectors. */
 deselect(); return RES_OK;
error:
 deselect(); status=STA_NOINIT; return RES_ERROR;
}
DRESULT disk_ioctl(BYTE p,BYTE cmd,void *buf) {
 if(p) return RES_PARERR;
 if(cmd==CTRL_SYNC) return status?RES_NOTRDY:RES_OK;
 if(cmd==GET_SECTOR_SIZE) { *(WORD*)buf=512; return RES_OK; }
 if(cmd==GET_BLOCK_SIZE) { *(DWORD*)buf=1; return RES_OK; }
 return RES_PARERR;
}
