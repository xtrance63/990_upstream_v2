# SPDX-License-Identifier: GPL-2.0
dtbo-y += samsung/exynos990-x1slte_eur_open_00.dtbo
dtbo-y += samsung/exynos990-x1slte_eur_open_21.dtbo

targets += dtbs
DTB_LIST  := $(dtb-y) $(dtbo-y)
always    := $(DTB_LIST)

dtbs: $(addprefix $(obj)/, $(DTB_LIST))

clean-files := *.dtb*
