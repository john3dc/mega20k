/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "platform.h"
static uint16_t candidate[2],stable[2],changed[2],queued;
static uint16_t sample(unsigned port) {
 uint16_t value=(port?IO(24):IO(4))&0x0fff;
 /* Opposing directions cannot come from a SNES D-pad. In particular, a
    stuck-low/disconnected data line must not turn every button on. */
 if((value&(UP|DOWN))==(UP|DOWN) || (value&(LEFT|RIGHT))==(LEFT|RIGHT))return 0;
 return value;
}
void input_poll(void) {
 uint16_t now=ticks();
 for(unsigned p=0;p<2;p++) {
  uint16_t value=sample(p);
  if(value!=candidate[p]) {candidate[p]=value;changed[p]=now;}
  /* Longer than the 16 ms pad scan: reject a single corrupt sample. */
  else if(value!=stable[p] && (uint16_t)(now-changed[p])>=20) {
   queued|=value&~stable[p];stable[p]=value;
  }
 }
}
uint16_t buttons(void) {input_poll();return stable[0]|stable[1];}
uint16_t input_pressed(void) {input_poll();uint16_t result=queued;queued=0;return result;}
void input_clear(void) {
 /* Consume keys held across a screen change, without waiting for release.
    Keep the ports separate so either pad can generate a fresh press. */
 uint16_t now=ticks();
 for(unsigned p=0;p<2;p++) {candidate[p]=stable[p]=sample(p);changed[p]=now;}
 queued=0;
}
