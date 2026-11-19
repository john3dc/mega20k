/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <string.h>
/* Keep compiler-generated memory calls available after LTO. */
__attribute__((used,externally_visible)) void *memcpy(void *d, const void *s, size_t n) { unsigned char *a=d; const unsigned char *b=s; while(n--) *a++=*b++; return d; }
__attribute__((used,externally_visible)) void *memset(void *d, int c, size_t n) { unsigned char *a=d; while(n--) *a++=c; return d; }
int memcmp(const void *a,const void *b,size_t n) { const unsigned char *x=a,*y=b; while(n--) {int d=*x++-*y++; if(d) return d;} return 0; }
size_t strlen(const char *s) { const char *p=s; while(*p) p++; return p-s; }
char *strchr(const char *s,int c) { do {if(*s==c) return (char*)s;} while(*s++); return 0; }
int strcmp(const char *a,const char *b) { while(*a && *a==*b) {a++;b++;} return (unsigned char)*a-(unsigned char)*b; }
