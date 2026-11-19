/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "core_flash.h"
#include <string.h>
static uint8_t read_buffer[512] __attribute__((aligned(2)));
static uint8_t x(uint8_t value) { return core_flash_transfer(value); }
static void end(void) { core_flash_select(0); }
static void command(uint8_t value) { core_flash_select(1);x(value); }
static void address(uint32_t value) { x(value>>16);x(value>>8);x(value); }
static uint8_t status(void) { command(5);uint8_t value=x(255);end();return value; }
static int ready(unsigned timeout) {
 uint16_t start=core_flash_ticks();
 do {if(!(status()&1))return 1;}while((uint16_t)(core_flash_ticks()-start)<timeout);return 0;
}
static int enable(void) { command(6);end();return (status()&3)==2; }
static int compare(const uint8_t *data,uint32_t bytes,unsigned first,unsigned span) {
 command(3);address(CORE_SLOT_ADDRESS);
 for(uint32_t pos=0;pos<bytes;) {
  unsigned n=bytes-pos>sizeof(read_buffer)?sizeof(read_buffer):bytes-pos;
  core_flash_read(read_buffer,n);
  if(memcmp(read_buffer,data+pos,n)){end();return 0;}
  pos+=n;
  if(!(pos&4095) || pos==bytes)core_progress(first+pos*span/bytes);
 }
 end();return 1;
}
int core_flash_stage(const uint8_t *data,const CoreInfo *info) {
 // Never erase or program the boot core. Validate the whole in-RAM image
 // again at this boundary, before the first flash write-enable command.
 if(info->address!=CORE_SLOT_ADDRESS || info->next || info->bytes<128 || info->bytes>CORE_SLOT_BYTES || !core_payload(data,info))return 0;
 core_progress(30);
 end();command(0x9f);uint8_t maker=x(255),type=x(255),density=x(255);end();
 // Standard 3-byte-address SPI NOR parts used on Nano 20K boards.
 if(!((maker==0x0b||maker==0xef||maker==0xc8||maker==0x9d||maker==0xc2) &&
      (type==0x40||type==0x60||type==0x20) && density>=0x15 && density<=0x18))return 0;
 if(!ready(3000) || (status()&0x3c))return 0;
 // XT25F64B/F (JEDEC 0b 40 17), the part identified on this board, supports
 // D8h 64-KiB block erase. Keep the existing 4-KiB path for other IDs.
 // The whole fixed 1-MiB slot belongs to the loader, including the padding
 // of the final erase block. No erase can reach the boot core or next slot.
 uint32_t erase_bytes=maker==0x0b && type==0x40 && density==0x17?65536:4096;
 // Reuse an identical staged image; ordinary switching need not wear flash.
 if(compare(data,info->bytes,30,15)){core_progress(99);return 1;}
 core_progress(45);
 unsigned previous=101;
 for(uint32_t pos=0;pos<info->bytes;pos+=erase_bytes) {
  if(!enable())return 0;command(erase_bytes==65536?0xd8:0x20);address(CORE_SLOT_ADDRESS+pos);end();if(!ready(3000))return 0;
  uint32_t limit=info->bytes-pos>erase_bytes?erase_bytes:info->bytes-pos;
  for(uint32_t page=0;page<limit;page+=256) {
   uint32_t n=limit-page>256?256:limit-page;
   if(!enable())return 0;command(2);address(CORE_SLOT_ADDRESS+pos+page);
   for(uint32_t i=0;i<n;i++)x(data[pos+page+i]);end();if(!ready(100))return 0;
   if(!((page+n)&4095) || page+n==limit) {
    unsigned percent=45+(pos+page+n)*40/info->bytes;
    if(percent!=previous){core_progress(percent);previous=percent;}
   }
  }
 }
 // Independent byte-for-byte readback after every erase/program has finished.
 unsigned match=compare(data,info->bytes,85,14);
 command(4);end(); // Write-disable also before FPGA reconfiguration.
 return match;
}

/* Persistent last-core selection. All fields are byte-encoded so 68000 and
   RV32 share the same journal. A record is committed by its CRC, after the
   addon has passed readback. The previous sector survives interrupted GC. */
#define BOOT_RECORD 128u
static uint8_t boot_record[BOOT_RECORD];
static uint32_t boot_location;
static uint32_t get32(const uint8_t *p) {
 return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];
}
static void put32(uint8_t *p,uint32_t n) {p[0]=n>>24;p[1]=n>>16;p[2]=n>>8;p[3]=n;}
static int boot_device(void) {
 end();command(0x9f);unsigned maker=x(255),type=x(255),density=x(255);end();
 return (maker==0x0b||maker==0xef||maker==0xc8||maker==0x9d||maker==0xc2) &&
  (type==0x40||type==0x60||type==0x20) && density>=0x16 && density<=0x18 &&
  ready(3000) && !(status()&0x3c);
}
static void read_at(uint32_t at,uint8_t *data,unsigned bytes) {
 command(3);address(at);core_flash_read(data,bytes);end();
}
static int record_valid(const uint8_t *p) {
 uint32_t size=get32(p+16);
 return !memcmp(p,"N20KBT01",8) && get32(p+12)==1 &&
  (!size || (size>=128 && size<=CORE_SLOT_BYTES)) &&
  p[24] && !p[55] && !p[87] && (p[120]==255 || !p[120]) &&
  core_crc32(0,p,120)==get32(p+124);
}
static int boot_read(void) {
 uint8_t candidate[BOOT_RECORD];boot_location=0;
 for(uint32_t at=CORE_BOOT_ADDRESS;at<CORE_BOOT_ADDRESS+CORE_BOOT_BYTES;at+=BOOT_RECORD) {
  read_at(at,candidate,sizeof(candidate));
  if(record_valid(candidate) && (!boot_location ||
     (int32_t)(get32(candidate+8)-get32(boot_record+8))>0)) {
   memcpy(boot_record,candidate,sizeof(candidate));boot_location=at;
  }
 }
 return boot_location!=0;
}
static int erased(uint32_t at) {
 uint8_t bytes[BOOT_RECORD];read_at(at,bytes,sizeof(bytes));
 for(unsigned i=0;i<sizeof(bytes);i++)if(bytes[i]!=255)return 0;
 return 1;
}
static int boot_program(uint32_t at,const uint8_t *data,unsigned size) {
 /* This boundary cannot write either FPGA bitstream. */
 if(at<CORE_BOOT_ADDRESS || at>=CORE_BOOT_ADDRESS+CORE_BOOT_BYTES ||
    !size || size>BOOT_RECORD || (at&255)+size>256 || !enable())return 0;
 command(2);address(at);for(unsigned i=0;i<size;i++)x(data[i]);end();
 int ok=ready(100);command(4);end();
 if(!ok)return 0;
 uint8_t check[BOOT_RECORD];read_at(at,check,size);
 return !memcmp(check,data,size);
}
static int boot_append(uint8_t *record) {
 uint32_t sector=boot_location?boot_location&~4095UL:CORE_BOOT_ADDRESS;
 uint32_t at=boot_location?boot_location+BOOT_RECORD:sector;
 while(at<sector+4096 && !erased(at))at+=BOOT_RECORD;
 if(at==sector+4096) {
  /* Erase only the sector that does not hold the latest committed record. */
  at=sector==CORE_BOOT_ADDRESS?CORE_BOOT_ADDRESS+4096:CORE_BOOT_ADDRESS;
  if(!enable())return 0;
  command(0x20);address(at);end();int ok=ready(3000);command(4);end();
  if(!ok)return 0;
 }
 put32(record+8,boot_location?get32(boot_record+8)+1:0);
 record[120]=255;put32(record+124,core_crc32(0,record,120));
 if(!boot_program(at,record,BOOT_RECORD))return 0;
 memcpy(boot_record,record,BOOT_RECORD);boot_location=at;return 1;
}
int core_flash_remember(const char *base,const CoreInfo *info) {
 if(!base[0] || strlen(base)>31 || !boot_device())return 0;
 boot_read();uint8_t record[BOOT_RECORD];memset(record,0,sizeof(record));
 memcpy(record,"N20KBT01",8);put32(record+12,1);memcpy(record+24,base,strlen(base));
 if(info && (info->flags&CORE_AUTOBOOT_RETURN)) {
  if(info->address!=CORE_SLOT_ADDRESS || info->next || info->bytes<128 ||
     info->bytes>CORE_SLOT_BYTES || !info->id[0] || info->id[31])return 0;
  put32(record+16,info->bytes);put32(record+20,info->crc);memcpy(record+56,info->id,32);
 }
 /* No program/erase on unchanged selection or ordinary power-on. */
 if(boot_location && boot_record[120]==255 && !memcmp(record+12,boot_record+12,108))return 1;
 return boot_append(record);
}
int core_flash_request_menu(void) {
 if(!boot_device())return 0;
 /* Legacy base cores have no selection record and cannot autoboot. */
 if(!boot_read() || !get32(boot_record+16) || !boot_record[120])return 1;
 uint8_t request=0;
 return boot_program(boot_location+120,&request,1);
}
int core_flash_boot(const char *base) {
 if(!boot_device() || !boot_read() || strcmp((char*)boot_record+24,base))return 0;
 if(!boot_record[120]) {
  uint8_t record[BOOT_RECORD];memcpy(record,boot_record,sizeof(record));
  /* If acknowledgement fails, keep requesting the menu on later boots. */
  boot_append(record);return 2;
 }
 uint32_t bytes=get32(boot_record+16),expected=get32(boot_record+20),crc=0;
 if(!bytes)return 0;
 command(3);address(CORE_SLOT_ADDRESS);
 for(uint32_t pos=0;pos<bytes;) {
  unsigned n=bytes-pos>sizeof(read_buffer)?sizeof(read_buffer):bytes-pos;
  core_flash_read(read_buffer,n);
  if(!pos) {
   for(unsigned i=0;i<22;i++)if(read_buffer[i]!=255){end();return 2;}
   if(memcmp(read_buffer+22,"\xa5\xc3\x06\x00\x00\x00\x00\x00\x08\x1b",10) ||
      memcmp(read_buffer+52,"\xd2\x00\xff\xff\0\0\0\0",8)){end();return 2;}
  }
  crc=core_crc32(crc,read_buffer,n);pos+=n;
 }
 end();return crc==expected?1:2;
}
