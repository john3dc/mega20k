/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "platform.h"
#include "ff.h"
#include "core_loader.h"
#include <string.h>
#define ROWS 22
#define NAME_WIDTH 35
#define ROM_ROOT "/megadrive"
#define ROOT_LEN (sizeof(ROM_ROOT)-1)
#define CORE_DIR "/cores"
#define CORE_DIR_LEN (sizeof(CORE_DIR)-1)
#define MAX_ENTRIES 2800
#define MAX_PATH 1024
#define MAX_ROM 0x700000UL
typedef struct { uint32_t size; uint16_t dir; char name[256]; } Entry;
static Entry *const entries=(Entry*)0x800000;
static uint16_t order[MAX_ENTRIES];
static Entry *entry(unsigned i) { return entries+order[i]; }
static FATFS fs;
static char path[MAX_PATH]=ROM_ROOT;
static unsigned count,selected,top;
static uint8_t buffer[16384] __attribute__((aligned(2)));
static char lower(char c) { return c>='A'&&c<='Z'?c+32:c; }
static int ci_compare(const char *a,const char *b) {
 while(*a && lower(*a)==lower(*b)) {a++;b++;} return (unsigned char)lower(*a)-(unsigned char)lower(*b);
}
static const char *extension(const char *s) { const char *p=s+strlen(s); while(p>s && *p!='.') p--; return *p=='.'?p:s+strlen(s); }
static int supported(const char *s) { const char *e=extension(s); return ci_compare(s,"core.bin") && (!ci_compare(e,".bin")||!ci_compare(e,".md")||!ci_compare(e,".gen")||!ci_compare(e,".smd")); }
static int compare(const Entry *a,const Entry *b) { return a->dir!=b->dir?(a->dir?-1:1):ci_compare(a->name,b->name); }
static void swap(unsigned a,unsigned b) { uint16_t temp=order[a];order[a]=order[b];order[b]=temp; }
/* In-place heap sort: bounded stack even with thousands of files. */
static void sift(unsigned root,unsigned end) {
 while(root*2+1<end) { unsigned c=root*2+1; if(c+1<end && compare(entry(c),entry(c+1))<0)c++; if(compare(entry(root),entry(c))>=0)break; swap(root,c);root=c; }
}
static void sort(void) { for(unsigned i=count/2;i;i--)sift(i-1,count); for(unsigned i=count;i>1;i--){swap(0,i-1);sift(0,i-1);} }
static void clear_screen(void) { for(unsigned y=0;y<28;y++)row(y,0,""); }
static void header(void) {
 row(0,0,"");row(1,0,"  Mega Drive");row(2,0,"");
 row(3,0,"");
}
static void busy(void) {
 clear_screen();header();text(18,14,0,"...",3);screen_present();
}
static void failure(void) {
 clear_screen();text(19,14,0,"!",1);screen_present();
 input_clear();while(!(input_pressed()&(A|B|START))){}input_clear();
}
void core_progress(unsigned percent) {
 static unsigned previous=101;
 if(!percent)clear_screen();else if(percent==previous)return;
 char n[12];number(n,percent);unsigned len=strlen(n);n[len++]='%';n[len]=0;
 row(14,0,"");text((40-len)/2,14,0,n,len);screen_present();previous=percent;
}
typedef struct {char title[256],file[272];} SystemEntry;
static SystemEntry *const systems=(SystemEntry*)0x800000;
static unsigned system_count;
static void system_draw(unsigned choice,unsigned first) {
 header();row(1,0,"  Systems");
 for(unsigned y=4;y<28;y++)row(y,0,"");
 for(unsigned y=0;y<ROWS && first+y<system_count;y++) {
  unsigned active=first+y==choice;row(5+y,active,"");
  text(1,5+y,active,active?">":" ",1);text(3,5+y,active,systems[first+y].title,NAME_WIDTH);
 }screen_present();
}
#ifndef MEGADRIVE_ADDON
static void system_menu(void) {
 DIR dir;FILINFO f;system_count=1;
 memcpy(systems[0].title,"megadrive20k",13);systems[0].file[0]=0;
 busy();
 if(!f_opendir(&dir,CORE_DIR)) {
  while(!f_readdir(&dir,&f) && f.fname[0] && system_count<64) {
   if(f.fname[0]=='.'||(f.fattrib&(AM_DIR|AM_HID|AM_SYS))||ci_compare(extension(f.fname),".bin"))continue;
   SystemEntry *e=systems+system_count;unsigned n=strlen(f.fname);
   if(n+CORE_DIR_LEN+2>sizeof(e->file))continue;
   memcpy(e->file,CORE_DIR,CORE_DIR_LEN);e->file[CORE_DIR_LEN]='/';
   memcpy(e->file+CORE_DIR_LEN+1,f.fname,n+1);
   FIL file;CoreInfo info;
   if(f_open(&file,e->file,FA_READ))continue;
   int valid=core_read_info(&file,&info);
   f_close(&file);if(!valid)continue;
   unsigned title_len=extension(f.fname)-f.fname;
   memcpy(e->title,f.fname,title_len);e->title[title_len]=0;
   if(!strcmp(info.id,CORE_BASE_ID)) {
    /* The installed base uses this row, never its duplicate addon file. */
    memcpy(systems[0].title,e->title,sizeof(e->title));continue;
   }
   if(!info.address)continue;
   system_count++;
  }f_closedir(&dir);
 }
 // Sort every system, including the installed base, by its displayed name.
 for(unsigned i=1;i<system_count;i++)for(unsigned j=i;j>0 && ci_compare(systems[j].title,systems[j-1].title)<0;j--) {
  SystemEntry temp=systems[j];systems[j]=systems[j-1];systems[j-1]=temp;
 }
 unsigned choice=0,first=0;system_draw(choice,first);
 input_clear();uint16_t prev=0,last=ticks(),held=last;
 for(;;) {
  uint16_t now=ticks(),keys=buttons(),press=input_pressed();
  if(keys!=prev)held=now;prev=keys;
  if((keys&(UP|DOWN)) && (uint16_t)(now-held)>350 && (uint16_t)(now-last)>65)press|=keys&(UP|DOWN);
  if(press&(B|SELECT)){input_clear();return;}
  if(press&(UP|DOWN)) {
   if((press&UP)&&choice)choice--;else if((press&DOWN)&&choice+1<system_count)choice++;
   if(choice<first)first=choice;if(choice>=first+ROWS)first=choice-ROWS+1;
   system_draw(choice,first);last=now;
  }
  if(press&(A|START)) {
   if(!systems[choice].file[0]) {
    if(!core_use_base()){failure();system_draw(choice,first);input_clear();prev=0;continue;}
    input_clear();return;
   }
   if(!core_load(systems[choice].file)) {
    failure();
    system_draw(choice,first);input_clear();prev=0;
   }
  }
 }
}
#else
static void system_menu(void) {
 if(!core_return_to_base())failure();
}
#endif
static FRESULT scan(void) {
 DIR d; FILINFO f; count=0; selected=top=0;
 busy();
 FRESULT r=f_opendir(&d,path); if(r) return r;
 while(!(r=f_readdir(&d,&f)) && f.fname[0]) {
  if(f.fname[0]=='.' || (f.fattrib&(AM_HID|AM_SYS)))continue;
  if((f.fattrib&AM_DIR) && strlen(path)==ROOT_LEN && !ci_compare(f.fname,"saves"))continue;
  if(!(f.fattrib&AM_DIR) && !supported(f.fname))continue;
  if(count==MAX_ENTRIES){break;}
  order[count]=count;Entry *e=entries+count++; e->dir=!!(f.fattrib&AM_DIR);
  e->size=f.fsize>0xffffffffULL?0xffffffffUL:(uint32_t)f.fsize;
  memcpy(e->name,f.fname,strlen(f.fname)+1);
 }
 f_closedir(&d);  if(!r)sort();  return r;
}
static void entry_row(unsigned line,unsigned offset) {
 unsigned i=top+line,y=5+line;
 if(i>=count){row(y,0,"");return;}
 Entry *e=entry(i); unsigned highlight=i==selected, pal=(e->dir?2:0)+highlight;
 row(y,highlight,"");text(1,y,highlight,highlight?">":" ",1);
 char display[256]; unsigned len=strlen(e->name);
 if(!e->dir) len=extension(e->name)-e->name;
 memcpy(display,e->name,len);display[len]=0;
 if(offset>len)offset=len;
 text(3,y,pal,display+offset,NAME_WIDTH);
}
static void draw(void) {
 header();row(4,0,"");for(unsigned y=0;y<ROWS;y++)entry_row(y,0);row(27,0,"");
 if(!count)text(19,14,0,"-",1);
 screen_present();
}
static int append_path(const char *name) {
 unsigned p=strlen(path),n=strlen(name); if(p+n+2>=MAX_PATH)return 0;
 if(p>1)path[p++]='/';memcpy(path+p,name,n+1);return 1;
}
static void parent(void) {unsigned n=strlen(path);if(n<=ROOT_LEN)return;while(n>ROOT_LEN && path[n-1]!='/')n--;if(n>ROOT_LEN)n--;path[n]=0;}
static void load_rom(const Entry *e) {
 FIL file; unsigned oldlen=strlen(path); uint8_t smd=!ci_compare(extension(e->name),".smd");
 if(!append_path(e->name)){failure();return;}
 FRESULT r=f_open(&file,path,FA_READ);path[oldlen]=0;if(r){failure();return;}
 uint32_t size=e->size-(smd?512:0);
 if(e->size<(smd?16896:512) || size>MAX_ROM || (size&1) || (smd && (size&16383))) {
  f_close(&file);failure();return;
 }
 if(smd)f_lseek(&file,512);
 core_progress(0);
 uint16_t last_progress=ticks();
 uint32_t pos=0;uint8_t pal=0,valid=0;
 while(pos<size) {
  UINT got,want=size-pos>sizeof(buffer)?sizeof(buffer):size-pos;
  uint8_t direct=!smd && pos!=0;
  IO(12)=pos>>22;
  void *target=direct?(void*)(uintptr_t)(0x400000+(pos&0x3fffff)):buffer;
  r=f_read(&file,target,want,&got); if(r || got!=want){f_close(&file);failure();return;}
  if(!pos) {
   uint8_t first[8];for(unsigned i=0;i<8;i++)first[i]=smd?buffer[(i&1)?i/2:8192+i/2]:buffer[i];
   uint32_t pc=((uint32_t)first[4]<<24)|((uint32_t)first[5]<<16)|((uint32_t)first[6]<<8)|first[7];
   valid=!(pc&1) && pc>=8 && pc<size;
   unsigned u=0,j=0,eu=0;
   for(unsigned i=0x1f0;i<0x200;i++) { char c=smd?buffer[(i&1)?i/2:8192+i/2]:buffer[i];u|=c=='U';j|=c=='J';eu|=c=='E'; }
   pal=eu&&!u&&!j;
  }
  if(!direct) {
   volatile uint16_t *dest=(volatile uint16_t*)(0x400000+(pos&0x3fffff));
   for(unsigned i=0;i<got;i+=2) *dest++=smd?((uint16_t)buffer[8192+i/2]<<8)|buffer[i/2]:((uint16_t)buffer[i]<<8)|buffer[i+1];
  }
  pos+=got;
  // Presenting the progress bar waits for vertical blank. Keep reading
  // between visible updates; completion is displayed below.
  if(pos<size && (uint16_t)(ticks()-last_progress)>=100) {
   core_progress(pos*99/size);
   last_progress=ticks();
  }
 }
 f_close(&file);
 if(!valid){failure();return;}
 if(!core_use_base()){failure();return;}
 core_progress(100);
 IO(8)=size>>16;IO(10)=size;IO(18)=pal;
  IO(14)=0x4d44; for(;;){}
}
int main(void) {
 screen_init();header();screen_present();
#ifndef MEGADRIVE_ADDON
 unsigned boot_menu=core_autostart();
#else
 unsigned boot_menu=0;
#endif
 for(;;) {
  FRESULT r=f_mount(&fs,"",1);if(r){failure();continue;}
  if(boot_menu){boot_menu=0;system_menu();}
  r=scan();if(r){failure();continue;}draw();input_clear();
  uint16_t prev=0,last=ticks(),held=last,marquee=last;unsigned offset=0;
  for(;;) {
   uint16_t now=ticks(),keys=buttons(),press=input_pressed();
   if(keys!=prev){held=now;}
   if((keys&(UP|DOWN)) && (uint16_t)(now-held)>350 && (uint16_t)(now-last)>65){press|=keys&(UP|DOWN);}
   prev=keys;
   if(press&(UP|DOWN)) {
    unsigned before=selected,oldtop=top;
    if((press&UP)&&selected)selected--;else if((press&DOWN)&&selected+1<count)selected++;
    if(selected<top)top=selected;if(selected>=top+ROWS)top=selected-ROWS+1;
    if(before!=selected){
     if(top!=oldtop)for(unsigned y=0;y<ROWS;y++)entry_row(y,0);
     else {entry_row(before-top,0);entry_row(selected-top,0);}
     screen_present();marquee=now;offset=0;
    }last=now;
   }
   if(count && (uint16_t)(now-marquee)>(offset?180:1000)) {
    Entry *e=entry(selected);unsigned len=e->dir?strlen(e->name):(unsigned)(extension(e->name)-e->name);
    if(len>NAME_WIDTH) {offset++;if(offset>len-NAME_WIDTH+7)offset=0;entry_row(selected-top,offset>len-NAME_WIDTH?len-NAME_WIDTH:offset);screen_present();}marquee=now;
   }
   if(press&SELECT){system_menu();break;}
   if((press&B) && strlen(path)>ROOT_LEN){parent();break;}
   if(count && (press&(A|START))) {
    if(entry(selected)->dir){if(append_path(entry(selected)->name))break;}
    else {load_rom(entry(selected));draw();input_clear();prev=0;}
   }
  }
 }
}
