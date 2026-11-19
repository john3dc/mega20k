/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef NANO_PLATFORM_H
#define NANO_PLATFORM_H
#include <stdint.h>
#include <stddef.h>
#define CORE_BASE_ID "megadrive20k"
#define REG16(a) (*(volatile uint16_t *)(uintptr_t)(a))
#ifndef IO
#define IO(n) REG16(0xa14000+(n))
#endif
enum { B=1, Y=2, SELECT=4, START=8, UP=16, DOWN=32, LEFT=64, RIGHT=128, A=256, X=512, L=1024, R=2048 };
/* Either physical SNES port can operate the launcher. Games keep two pads. */
uint16_t buttons(void);
static inline uint16_t ticks(void) { return IO(6); } /* milliseconds, wraps */
static inline void delay_ms(uint16_t n) { uint16_t t=ticks(); while((uint16_t)(ticks()-t)<n) {} }
void screen_init(void);
void screen_present(void);
void input_poll(void);
uint16_t input_pressed(void);
void input_clear(void);
void row(unsigned y,unsigned palette,const char *s);
void text(unsigned x,unsigned y,unsigned palette,const char *s,unsigned width);
void number(char *out,unsigned n);
#endif
