/*
 * Copyright (c) 2025, The Linux Foundation. All rights reserved.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 and
 * only version 2 as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#include <linux/export.h>
#include <linux/types.h>

static bool bootanim_set_brightness = false;

void set_fixed_brightness(int* brightness)
{
	// Only work around this if we are past boot animation.
	if (bootanim_set_brightness)
		*brightness *= 100;
	else
		bootanim_set_brightness = true;
}

EXPORT_SYMBOL_GPL(set_fixed_brightness);