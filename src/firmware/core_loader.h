/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef NANO_CORE_LOADER_H
#define NANO_CORE_LOADER_H
#include "ff.h"
#include "core_format.h"
int core_read_info(FIL *file,CoreInfo *info);
int core_load(const char *path);
int core_autostart(void);
int core_use_base(void);
int core_return_to_base(void);
#endif
