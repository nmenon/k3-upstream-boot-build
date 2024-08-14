# Build everything out of tree
O ?= build
override O := $(abspath $(O))

# Interim deployment binaries
I ?= $(O)/intermediate
override I := $(abspath $(I))

ROOT_DIR= $(shell pwd)
CONFIG_DIR=$(ROOT_DIR)/configs
TFA_DIR ?= $(ROOT_DIR)/arm-trusted-firmware
OPTEE_DIR ?= $(ROOT_DIR)/optee_os
UBOOT_DIR ?= $(ROOT_DIR)/u-boot
FW_DIR ?= $(ROOT_DIR)/ti-linux-firmware

unexport CROSS_COMPILE
unexport CROSS_COMPILE64
unexport ARCH

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

ifeq ($(SECURITY_TYPE),gp)
	SECTYPE_EXT = _unsigned
endif

# Final deployment binaries
ifndef D
D = deploy/$(SOC_NAME)_$(BOARD_NAME)_$(SECURITY_TYPE)
endif
override D := $(abspath $(D))

.PHONY: all
all: u_boot

.PHONY: u_boot
ifndef SOC_NAME
u_boot: help
	$(Q)echo "Please Select a defconfig"
	$(Q)echo
	$(Q)exit 1
else
u_boot: u_boot_r5 u_boot_armv8
	$(Q)echo "BUILD COMPLETE: SoC=$(SOC_NAME) Board=$(BOARD_NAME) SECURITY=$(SECURITY_TYPE)"
endif

%defconfig: $(CONFIG_DIR)/%defconfig $(O)
	$(Q)cp $< $(O)/.config

.PHONY: tfa
tfa: $(O) $(I)
	$(Q)$(MAKE) -C $(TFA_DIR) BUILD_BASE=$(O)/arm-trusted-firmware CROSS_COMPILE=$(CROSS_COMPILE_64) ARCH=aarch64 PLAT=k3 TARGET_BOARD=$(TFA_BOARD) $(TFA_EXTRA_ARGS) SPD=opteed DEBUG=1 all
	$(Q)cp -v $(O)/arm-trusted-firmware/k3/$(TFA_BOARD)/debug/bl31.bin $(I)

.PHONY: optee
optee: $(O) $(I)
	$(Q)$(MAKE) -C $(OPTEE_DIR) O=$(O)/optee CROSS_COMPILE=$(CROSS_COMPILE_32) CROSS_COMPILE64=$(CROSS_COMPILE_64) PLATFORM=$(OPTEE_PLATFORM) $(OPTEE_EXTRA_ARGS) CFG_TEE_CORE_LOG_LEVEL=2 CFG_TEE_CORE_DEBUG=y CFG_ARM64_core=y all
	$(Q)cp -v $(O)/optee/core/tee-raw.bin $(I)

.PHONY: u_boot_r5
u_boot_r5: $(O) $(D)
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_32) O=$(O)/u-boot/r5 $(UBOOT_ARMV7_DEFCONFIG)
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_32) O=$(O)/u-boot/r5 BINMAN_INDIRS=$(FW_DIR)
	$(Q)cp -v $(O)/u-boot/r5/tiboot3-$(SOC_NAME)-$(SECURITY_TYPE)-evm.bin $(D)/tiboot3.bin
	$(Q)if [ -f $(O)/u-boot/r5/sysfw-$(SOC_NAME)-$(SECURITY_TYPE)-evm.itb ]; then \
		cp -v $(O)/u-boot/r5/sysfw-$(SOC_NAME)-$(SECURITY_TYPE)-evm.itb $(D)/sysfw.itb; \
	fi
	$(Q)cp -v $(O)/u-boot/r5/*-capsule.bin $(D) 2>/dev/null || true

.PHONY: u_boot_armv8
u_boot_armv8: $(O) $(D) optee tfa
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_64) O=$(O)/u-boot/armv8 $(UBOOT_ARMV8_DEFCONFIG)
	$(Q)$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(CROSS_COMPILE_64) O=$(O)/u-boot/armv8 BINMAN_INDIRS=$(FW_DIR) \
					BL31=$(I)/bl31.bin \
					TEE=$(I)/tee-raw.bin
	$(Q)cp -v $(O)/u-boot/armv8/tispl.bin$(SECTYPE_EXT) $(D)/tispl.bin
	$(Q)cp -v $(O)/u-boot/armv8/u-boot.img$(SECTYPE_EXT) $(D)/u-boot.img
	$(Q)cp -v $(O)/u-boot/armv8/*-capsule.bin $(D) 2>/dev/null || true

$(O):
	$(Q)mkdir -p $(O)

$(D):
	$(Q)mkdir -p $(D)

$(I): $(O)
	$(Q)mkdir -p $(I)

.PHONY: sdcard
sdcard: u_boot $(I) $(D)
# Create image with partition table
	$(Q)dd if=/dev/zero of=$(D)/sdcard.img bs=1M count=28
	$(Q)parted --script $(D)/sdcard.img \
		mklabel msdos \
		mkpart primary fat16 4MiB 20MiB \
		mkpart primary fat16 20MiB 100% \
		set 1 boot on \
		set 1 bls_boot off \
		set 1 lba on \
		set 2 esp on
# Create FAT16 boot partition
	$(Q)dd if=/dev/zero of=$(I)/boot-partition.raw bs=1M count=16
	$(Q)mkfs.vfat $(I)/boot-partition.raw
# Create FAT16 ESP partition
	$(Q)dd if=/dev/zero of=$(I)/esp-partition.raw bs=1M count=8
	$(Q)mkfs.vfat $(I)/esp-partition.raw
# Copy boot artifacts to boot partition
	$(Q)mcopy -i $(I)/boot-partition.raw $(D)/tiboot3.bin ::tiboot3.bin
	$(Q)mcopy -i $(I)/boot-partition.raw $(D)/tispl.bin ::tispl.bin
	$(Q)mcopy -i $(I)/boot-partition.raw $(D)/u-boot.img ::u-boot.img
	$(Q)mcopy -i $(I)/boot-partition.raw $(D)/sysfw.itb ::sysfw.itb 2>/dev/null || true
	$(Q)mcopy -i $(I)/boot-partition.raw scripts/srf_uenv.txt ::uEnv.txt
# Copy boot partition to image
	$(Q)dd if=$(I)/boot-partition.raw of=$(D)/sdcard.img bs=1M seek=4 conv=notrunc
# Copy capsules to ESP partition
	$(Q)mmd -i $(I)/esp-partition.raw ::EFI
	$(Q)mmd -i $(I)/esp-partition.raw ::EFI/UpdateCapsule
	$(Q)mcopy -i $(I)/esp-partition.raw $(D)/*-capsule.bin ::EFI/UpdateCapsule 2>/dev/null || true
# Copy esp partition to image
	$(Q)dd if=$(I)/esp-partition.raw of=$(D)/sdcard.img bs=1M seek=20 conv=notrunc
# Save a bit of disk space by compressing the sdcard image
	$(Q)xz -ef $(D)/sdcard.img
	$(Q)echo "SDCARD IMG COMPLETE: SoC=$(SOC_NAME) Board=$(BOARD_NAME) SECURITY=$(SECURITY_TYPE)"

.PHONY: mrproper
mrproper:
	$(Q)rm -rvf $(O) $(I) $(D)

.PHONY: git
git:
	$(Q)git submodule status|grep '^-' && git submodule init && \
		git submodule update || echo 'Git submodules: nothin to update'

.PHONY: gitsync
gitsync:
	$(Q)git submodule init && git submodule sync && \
		git submodule update --remote && \
		echo 'Git submodules: nothin to sync'

.PHONY: gitclean
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

.PHONY: gitdeinit
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

.PHONY: gitdesc
gitdesc: git
	$(Q)$(shell git submodule foreach \
		'echo "    "`git rev-parse --abbrev-ref HEAD`" @"\
			`git describe --always --dirty` ":"\
			`git ls-remote --get-url`'\
		1>&2)
	$(Q)$(shell echo "I am at: "`git rev-parse --abbrev-ref HEAD` \
			"@" `git describe --always --dirty` ":"\
			`git ls-remote --get-url` 1>&2)

.PHONY: help
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
