/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "platform.h"
#include "font8x8_basic.h"
#define DATA REG16(0xc00000)
#define CTRL REG16(0xc00004)
static uint16_t cells[28][40];
static uint32_t dirty;
static uint16_t back=0xa000;
static void address(unsigned a,unsigned code) {
 CTRL=(a&0x3fff)|((code&3)<<14); CTRL=(a>>14)|((code&0x3c)<<2);
}
static void reg(unsigned r,unsigned v) { CTRL=0x8000|(r<<8)|v; }
static void word(uint16_t v) { while(CTRL&0x100) {} DATA=v; }
void screen_init(void) {
 /* H40, 224 lines, plane A at C000, B at E000, no interrupts or DMA. */
 static const uint8_t regs[24]={4,4,0x30,0x3c,7,0x78,0,0,0,0,0,0,0x81,0x3e,0,2,1,0,0,0,0,0,0,0};
 for(unsigned i=0;i<24;i++) reg(i,regs[i]);
 /* VSRAM is separate from VRAM and survives a warm core reset. Clear both
    planes/all 20 columns before enabling the menu, plus its H-scroll pair. */
 address(0,5);
 for(unsigned i=0;i<40;i++)word(0);
 address(0xf800,1);word(0);word(0);
 address(0,3);
 for(unsigned p=0;p<4;p++) for(unsigned c=0;c<16;c++) {
  uint16_t fg=p>=2?0x0ee:0xeee; /* directories: yellow, selected or not */
  word(c==1?fg:c==2?((p&1)?0x842:0x200):0x200);
 }
 address(0,1);
 for(unsigned c=0;c<128;c++) for(unsigned y=0;y<8;y++) {
  uint32_t pixels=0;
  for(unsigned x=0;x<8;x++) pixels=(pixels<<4)|((font8x8_basic[c][y]&(1<<x))?1:2);
  word(pixels>>16); word(pixels);
 }
 for(unsigned y=0;y<28;y++) row(y,0,"");
 reg(1,0x44);
 screen_present();
}
static unsigned glyph(unsigned char c) {
 /* CP437 filenames stay unchanged on disk; readable fallback on screen. */
 if(c>=32 && c<127) return c;
 switch(c) {case 0x84:case 0x8e:return 'a';case 0x94:case 0x99:return 'o';case 0x81:case 0x9a:return 'u';case 0x82:return 'e';case 0xe1:return 's';}
 return '?';
}
void text(unsigned x,unsigned y,unsigned palette,const char *s,unsigned width) {
 for(unsigned i=0;i<width;i++)cells[y][x+i]=(palette<<13)|(*s?glyph(*s++):32);
 dirty|=1UL<<y;
}
void row(unsigned y,unsigned palette,const char *s) { text(0,y,palette,s,40); }
static void upload(uint16_t base,uint32_t changed) {
 for(unsigned y=0;y<28;y++)if(changed&(1UL<<y)) {
  input_poll();
  address(base+y*128,1);for(unsigned x=0;x<40;x++)word(cells[y][x]);
 }
}
void screen_present(void) {
 if(!dirty)return;
 uint32_t changed=dirty;dirty=0;upload(back,changed);
 /* Change the plane table in vertical blank, after the last active line.
    The front image is always complete, including during continuous scroll. */
 while(CTRL&8){input_poll();} while(!(CTRL&8)){input_poll();} while(!(CTRL&4)){input_poll();}
 reg(2,back>>10);back=back==0xa000?0xc000:0xa000;
 upload(back,changed);
}
void number(char *out,unsigned n) {
 char tmp[11]; unsigned i=0; do {tmp[i++]='0'+n%10;n/=10;} while(n);
 while(i) *out++=tmp[--i]; *out=0;
}
