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
SECDEV_DIR=$(ROOT_DIR)/core-secdev-k3

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

ifneq ($(SECURITY_TYPE),gp)
	HS_EXT = .signed
	HS_UBOOTEXT = _HS
endif

ifneq ($(DM_COMBINED_WITH_TIFS),1)
	DM_SOC_NAME ?= $(SOC_NAME)
	DMCONF="DM=$(I)/ipc_echo_testb_mcu1_0_release_strip.xer5f$(HS_EXT)"
endif

ifndef SOC_NAME
all: help
	$(Q)echo "Please Select a defconfig"
else
all: k3imggen u_boot
	$(Q)echo "BUILD COMPLETE: SoC=$(SOC_NAME) Board=$(BOARD_NAME) SECURITY=$(SECURITY_TYPE)"
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
	$(Q)$(MAKE) -C $(K3IMGGEN_DIR) SOC=$(K3IMGGEN_SOC) SOC_TYPE=$(SECURITY_TYPE) CONFIG=evm CROSS_COMPILE=$(CROSS_COMPILE_32) \
			SYSFW_DIR=$(FW_DIR)/ti-sysfw O=$(O)/k3-img-gen TI_SECURE_DEV_PKG=$(SECDEV_DIR) SBL=$(I)/u-boot-spl.bin mrproper
	$(Q)$(MAKE) -C $(K3IMGGEN_DIR) SOC=$(K3IMGGEN_SOC) SOC_TYPE=$(SECURITY_TYPE) CONFIG=evm CROSS_COMPILE=$(CROSS_COMPILE_32) \
			SYSFW_DIR=$(FW_DIR)/ti-sysfw O=$(O)/k3-img-gen TI_SECURE_DEV_PKG=$(SECDEV_DIR) SBL=$(I)/u-boot-spl.bin
	$(Q)cp -v $(K3IMGGEN_DIR)/tiboot3.bin $(D)

k3imggen_legacy: $(O) $(D)
	$(Q)$(MAKE) -C $(K3IMGGEN_DIR) SOC=$(K3IMGGEN_SOC) SOC_TYPE=$(SECURITY_TYPE) CONFIG=evm CROSS_COMPILE=$(CROSS_COMPILE_32) \
			SYSFW_DIR=$(FW_DIR)/ti-sysfw O=$(O)/k3-img-gen TI_SECURE_DEV_PKG=$(SECDEV_DIR) mrproper
	$(Q)$(MAKE) -C $(K3IMGGEN_DIR) SOC=$(K3IMGGEN_SOC) SOC_TYPE=$(SECURITY_TYPE) CONFIG=evm CROSS_COMPILE=$(CROSS_COMPILE_32) \
			SYSFW_DIR=$(FW_DIR)/ti-sysfw O=$(O)/k3-img-gen TI_SECURE_DEV_PKG=$(SECDEV_DIR) SYFW_DIR=$(FW_DIR)/ti-sysfw
	$(Q)cp -v $(K3IMGGEN_DIR)/sysfw.itb $(D)

tfa: $(O) $(I)
	$(Q)$(MAKE) -C $(TFA_DIR) BUILD_BASE=$(O)/arm-trusted-firmware CROSS_COMPILE=$(CROSS_COMPILE_64) ARCH=aarch64 PLAT=k3 TARGET_BOARD=$(TFA_BOARD) $(TFA_EXTRA_ARGS) SPD=opteed all
	$(Q)cp -v $(O)/arm-trusted-firmware/k3/$(TFA_BOARD)/release/bl31.bin $(I)
ifneq ($(SECURITY_TYPE),gp)
	$(SECDEV_DIR)/scripts/secure-binary-image.sh $(O)/arm-trusted-firmware/k3/$(TFA_BOARD)/release/bl31.bin $(O)/arm-trusted-firmware/k3/$(TFA_BOARD)/release/bl31.bin$(HS_EXT)
	$(Q)cp -v $(O)/arm-trusted-firmware/k3/$(TFA_BOARD)/release/bl31.bin$(HS_EXT) $(I)
endif

optee: $(O) $(I)
	$(Q)$(MAKE) -C $(OPTEE_DIR) O=$(O)/optee CROSS_COMPILE=$(CROSS_COMPILE_32) CROSS_COMPILE64=$(CROSS_COMPILE_64) PLATFORM=$(OPTEE_PLATFORM) $(OPTEE_EXTRA_ARGS) CFG_TEE_CORE_LOG_LEVEL=2 CFG_TEE_CORE_DEBUG=y CFG_ARM64_core=y all
	$(Q)cp -v $(O)/optee/core/tee-pager_v2.bin $(I)/
ifneq ($(SECURITY_TYPE),gp)
	$(SECDEV_DIR)/scripts/secure-binary-image.sh $(O)/optee/core/tee-pager_v2.bin $(O)/optee/core/tee-pager_v2.bin$(HS_EXT)
	$(Q)cp -v $(O)/optee/core/tee-pager_v2.bin$(HS_EXT) $(I)/
endif

dm: $(I)
ifneq ($(DM_COMBINED_WITH_TIFS),1)
	$(Q)cp -v $(FW_DIR)/ti-dm/$(DM_SOC_NAME)/ipc_echo_testb_mcu1_0_release_strip.xer5f $(I)
ifneq ($(SECURITY_TYPE),gp)
	$(SECDEV_DIR)/scripts/secure-binary-image.sh $(I)/ipc_echo_testb_mcu1_0_release_strip.xer5f $(I)/ipc_echo_testb_mcu1_0_release_strip.xer5f$(HS_EXT)
endif
endif

u_boot_r5: $(O) $(I)
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_32) ARCH=arm TI_SECURE_DEV_PKG=$(SECDEV_DIR) O=$(O)/u-boot/r5 $(UBOOT_ARMV7_DEFCONFIG)
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_32) ARCH=arm TI_SECURE_DEV_PKG=$(SECDEV_DIR) O=$(O)/u-boot/r5
ifeq ($(MULTICERTIFICATE_BOOT_CAPABLE),1)
	$(Q)cp -v $(O)/u-boot/r5/spl/u-boot-spl.bin $(I)
else
	$(Q)cp -v $(O)/u-boot/r5/tiboot3.bin $(D)
endif

u_boot_armv8: $(O) $(D) optee tfa dm
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_64) ARCH=arm TI_SECURE_DEV_PKG=$(SECDEV_DIR) O=$(O)/u-boot/armv8 $(UBOOT_ARMV8_DEFCONFIG)
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_64) ARCH=arm TI_SECURE_DEV_PKG=$(SECDEV_DIR) O=$(O)/u-boot/armv8 \
					ATF=$(I)/bl31.bin$(HS_EXT) \
				  TEE=$(I)/tee-pager_v2.bin$(HS_EXT) \
				  $(DMCONF)
	$(Q)cp -v $(O)/u-boot/armv8/tispl.bin$(HS_UBOOTEXT) $(D)/tispl.bin
	$(Q)cp -v $(O)/u-boot/armv8/u-boot.img$(HS_UBOOTEXT) $(D)/u-boot.img

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
