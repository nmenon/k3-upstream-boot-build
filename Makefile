# Build everything out of tree
O ?= build
override O := $(abspath $(O))

# Interim deployment binaries
I ?= $(O)/intermediate
override I := $(abspath $(I))

# Final deployment binaries
D ?= deploy
override D := $(abspath $(D))

ROOT_DIR= $(shell pwd)
CONFIG_DIR=$(ROOT_DIR)/configs
TFA_DIR ?= $(ROOT_DIR)/arm-trusted-firmware
OPTEE_DIR ?= $(ROOT_DIR)/optee_os
UBOOT_DIR ?= $(ROOT_DIR)/u-boot
K3IMGGEN_DIR=$(ROOT_DIR)/k3-image-gen
FW_DIR=$(ROOT_DIR)/ti-linux-firmware

unexport CROSS_COMPILE
unexport CROSS_COMPILE64

# Handle verbose
ifeq ("$(origin V)", "command line")
  VERBOSE = $(V)
endif
VERBOSE ?= 0
Q := $(if $(VERBOSE:1=),@)

# 64bit Defaults
CROSS_COMPILE_64 ?= aarch64-none-linux-gnu-

# 32bit Defaults
CROSS_COMPILE_32 ?= arm-none-linux-gnueabihf-

-include $(O)/.config

ifneq ($(DM_COMBINED_WITH_TIFS),1)
	DMCONF="DM=$(abspath $(FW_DM_PATH))"
endif
ifndef SOC_NAME
all: help
	$(Q)echo "Please Select a defconfig"
else
all: k3imggen u_boot
	$(Q)echo "BUILD COMPLETE: SoC=$(SOC_NAME) Board=$(BOARD_NAME) SECURITY=$(SECURITY_TYPE) BOOTTYPE=$(BOOTTYPE)"
endif

%defconfig: $(CONFIG_DIR)/%defconfig $(O)
	$(Q)cp $< $(O)/.config

ifeq ($(MULTICERTIFICATE_BOOT_CAPABLE),1)
k3imggen: k3imggen_multicert
	$(Q)echo "Multi-certificate k3imggen built"
else
k3imggen: k3imggen_legacy
	$(Q)echo "Legacy k3imggen (non-multi-certificate) built"
endif

k3imggen_multicert: $(O) $(D) u_boot_r5
	$(Q)cd k3-image-gen && \
	    $(MAKE) SOC=$(K3IMGGEN_SOC) CONFIG=evm CROSS_COMPILE=$(CROSS_COMPILE_32) O=$(O)/k3-img-gen \
		SBL=$(I)/u-boot-spl.bin mrproper && \
	    $(MAKE) SOC=$(K3IMGGEN_SOC) CONFIG=evm CROSS_COMPILE=$(CROSS_COMPILE_32) O=$(O)/k3-img-gen \
		SYSFW_PATH=$(abspath $(FW_TIFS_PATH)) \
		SBL=$(I)/u-boot-spl.bin && \
	    cp -v tiboot3.bin $(D)

k3imggen_legacy: $(O) $(D)
	$(Q)cd $(K3IMGGEN_DIR) &&\
	    $(MAKE) SOC=$(K3IMGGEN_SOC) CONFIG=evm CROSS_COMPILE=$(CROSS_COMPILE_32) O=$(O)/k3-img-gen mrproper && \
	    $(MAKE) SOC=$(K3IMGGEN_SOC) CONFIG=evm CROSS_COMPILE=$(CROSS_COMPILE_32) O=$(O)/k3-img-gen \
	    SYSFW_PATH=$(abspath $(FW_TIFS_PATH))&& \
	    cp -v sysfw.itb $(D)

tfa: $(O) $(I)
	$(Q)$(MAKE) -C $(TFA_DIR) BUILD_BASE=$(O)/arm-trusted-firmware CROSS_COMPILE=$(CROSS_COMPILE_64) ARCH=aarch64 PLAT=k3 TARGET_BOARD=$(TFA_BOARD) $(TFA_EXTRA_ARGS) SPD=opteed all
	$(Q)cp -v $(O)/arm-trusted-firmware/k3/$(TFA_BOARD)/release/bl31.bin $(I)

optee: $(O) $(I)
	$(Q)$(MAKE) -C $(OPTEE_DIR) O=$(O)/optee CROSS_COMPILE=$(CROSS_COMPILE_32) CROSS_COMPILE64=$(CROSS_COMPILE_64) PLATFORM=$(OPTEE_PLATFORM) $(OPTEE_EXTRA_ARGS) CFG_TEE_CORE_LOG_LEVEL=2 CFG_TEE_CORE_DEBUG=y CFG_ARM64_core=y all
	$(Q)cp -v $(O)/optee/core/tee-pager_v2.bin $(I)/

ifeq ($(MULTICERTIFICATE_BOOT_CAPABLE),1)
u_boot_r5: u_boot_r5_multicert
	$(Q)echo "Multi-certificate u-boot-r5 built"
else
u_boot_r5: u_boot_r5_legacy
	$(Q)echo "Legacy u-boot-r5 (non-multi-certificate) built"
endif

u_boot_r5_multicert: $(O) $(I)
	$(Q)$(MAKE) -C u-boot CROSS_COMPILE=$(CROSS_COMPILE_32) ARCH=arm O=$(O)/u-boot/r5 $(UBOOT_ARMV7_DEFCONFIG)
	$(Q)$(MAKE) -C u-boot CROSS_COMPILE=$(CROSS_COMPILE_32) ARCH=arm O=$(O)/u-boot/r5
	$(Q)cp -v $(O)/u-boot/r5/spl/u-boot-spl.bin $(I)

u_boot_r5_legacy: $(O) $(D)
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_32) ARCH=arm O=$(O)/u-boot/r5 $(UBOOT_ARMV7_DEFCONFIG)
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_32) ARCH=arm O=$(O)/u-boot/r5
	$(Q)cp -v $(O)/u-boot/r5/tiboot3.bin $(D)

u_boot_armv8: $(O) $(D) optee tfa
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_64) ARCH=arm O=$(O)/u-boot/armv8 $(UBOOT_ARMV8_DEFCONFIG)
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_64) ARCH=arm O=$(O)/u-boot/armv8 \
				  ATF=$(I)/bl31.bin \
				  TEE=$(I)/tee-pager_v2.bin \
				  $(DMCONF)
	$(Q) cp -v $(O)/u-boot/armv8/tispl.bin $(D)
	$(Q) cp -v $(O)/u-boot/armv8/u-boot.img $(D)

u_boot: u_boot_r5 u_boot_armv8
	$(Q)echo "U-boot Build complete"

$(O):
	$(Q)mkdir -p $(O)

$(D):
	$(Q)mkdir -p $(D)

$(I): $(O)
	$(Q)mkdir -p $(I)

mrproper:
	$(Q)rm -rvf $(O) $(I) $(D)
	$(Q)cd $(K3IMGGEN_DIR) && git clean -fdx

git:
	$(Q)git submodule status|grep '^-' && git submodule init && \
		git submodule update || echo 'Git submodules: nothin to update'

gitsync:
	$(Q)git submodule init && git submodule sync && \
		git submodule update --remote && \
		echo 'Git submodules: nothin to sync'

gitclean:
	$(Q)echo 'WARNING WARNING WARNING'
	$(Q)echo 'git clean -fdx;git reset --hard everything (including all submodules)!'
	$(Q)echo 'ALL LOCAL CHANGES, uncommited changes, untracked files ARE NUKED/WIPED OUT!!!!!!!!'
	$(Q)read -p 'Enter "y" to continue - any other character to abort: ' confirm;\
	if [ "$$confirm" != y ]; then echo "Aborting"; exit 1; fi;\
	echo "Cleaning!"
	$(Q)$(shell git submodule foreach git clean -fdx >/dev/null)
	$(Q)$(shell git submodule foreach git reset --hard >/dev/null)
	$(Q)git clean -fdx
	$(Q)git reset --hard

gitdeinit:
	$(Q)echo 'WARNING WARNING WARNING'
	$(Q)echo 'git submodule deinit --all -f  -> This will WIPE OUT every git submodule details!!!'
	$(Q)echo 'git clean -fdx;git reset --hard everything (including all submodules)!'
	$(Q)echo 'ALL LOCAL CHANGES, uncommited changes, untracked files ARE NUKED/WIPED OUT!!!!!!!!'
	$(Q)read -p 'Enter "y" to continue - any other character to abort: ' confirm;\
	if [ "$$confirm" != y ]; then echo "Aborting"; exit 1; fi;\
	echo "Cleaning!"
	$(Q)$(shell git submodule foreach git clean -fdx >/dev/null)
	$(Q)$(shell git submodule foreach git reset --hard >/dev/null)
	$(Q)git clean -fdx
	$(Q)git reset --hard
	$(Q)git submodule deinit --all -f

gitdesc: git
	$(Q)$(shell git submodule foreach \
		'echo "    "`git rev-parse --abbrev-ref HEAD`" @"\
			`git describe --always --dirty` ":"\
			`git ls-remote --get-url`'\
		1>&2)
	$(Q)$(shell echo "I am at: "`git rev-parse --abbrev-ref HEAD` \
			"@" `git describe --always --dirty` ":"\
			`git ls-remote --get-url` 1>&2)

help:
	$(Q)echo
	$(Q)echo "help:"
	$(Q)echo
	$(Q)echo "Please read README.md for complete details"
	$(Q)echo
	$(Q)echo "Basic steps:"
	$(Q)echo "make soc_board_gp_all_defconfig"
	$(Q)echo "make"
	$(Q)echo
	$(Q)echo "Available defconfigs"
	$(Q)cd $(CONFIG_DIR);ls *defconfig|sort|nl
	$(Q)echo
