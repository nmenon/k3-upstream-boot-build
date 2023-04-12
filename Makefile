# Build everything out of tree
O ?= build
override O := $(abspath $(O))

# Interim deployment binaries
I ?= $(O)/intermediate
override I := $(abspath $(I))

# Final deployment binaries
D ?= deploy
override D := $(abspath $(D))

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

all: k3imggen u_boot
	$(Q)echo "J721E bootloader build Complete"


k3imggen: $(O) $(D)
	$(Q)cd k3-image-gen &&\
	    $(MAKE) SOC=j721e CONFIG=evm CROSS_COMPILE=$(CROSS_COMPILE_32) O=$(O)/k3-img-gen mrproper && \
	    $(MAKE) SOC=j721e CONFIG=evm CROSS_COMPILE=$(CROSS_COMPILE_32) O=$(O)/k3-img-gen \
	    SYSFW_PATH=$(abspath ti-linux-firmware/ti-sysfw/ti-fs-firmware-j721e-gp.bin)&& \
	    cp -v sysfw.itb $(D)

tfa: $(O) $(I)
	$(Q)$(MAKE) -C arm-trusted-firmware BUILD_BASE=$(O)/arm-trusted-firmware CROSS_COMPILE=$(CROSS_COMPILE_64) ARCH=aarch64 PLAT=k3 TARGET_BOARD=generic SPD=opteed all
	$(Q)cp -v $(O)/arm-trusted-firmware/k3/generic/release/bl31.bin $(I)

optee: $(O) $(I)
	$(Q)$(MAKE) -C optee_os O=$(O)/optee CROSS_COMPILE=$(CROSS_COMPILE_32) CROSS_COMPILE64=$(CROSS_COMPILE_64) PLATFORM=k3 CFG_TEE_CORE_LOG_LEVEL=2 CFG_ARM64_core=y all
	$(Q)cp -v $(O)/optee/core/tee-pager_v2.bin $(I)/

u_boot_r5: $(O) $(D)
	$(Q)$(MAKE) -C u-boot CROSS_COMPILE=$(CROSS_COMPILE_32) ARCH=arm O=$(O)/u-boot/r5 j721e_evm_r5_defconfig
	$(Q)$(MAKE) -C u-boot CROSS_COMPILE=$(CROSS_COMPILE_32) ARCH=arm O=$(O)/u-boot/r5
	$(Q)cp -v $(O)/u-boot/r5/tiboot3.bin $(D)

u_boot_armv8: $(O) $(D) optee tfa
	$(Q)$(MAKE) -C u-boot CROSS_COMPILE=$(CROSS_COMPILE_64) ARCH=arm O=$(O)/u-boot/armv8 j721e_evm_a72_defconfig
	$(Q)$(MAKE) -C u-boot CROSS_COMPILE=$(CROSS_COMPILE_64) ARCH=arm O=$(O)/u-boot/armv8 \
				  ATF=$(I)/bl31.bin \
				  TEE=$(I)/tee-pager_v2.bin \
				  DM=$(abspath ti-linux-firmware/ti-dm/j721e/ipc_echo_testb_mcu1_0_release_strip.xer5f)
	$(Q) cp -v $(O)/u-boot/armv8/tispl.bin $(D)
	$(Q) cp -v $(O)/u-boot/armv8/u-boot.img $(D)

u_boot: u_boot_r5 u_boot_armv8
	$(Q)echo "U-boot Build complete"

$(O):
	$(Q)mkdir -p $(O)
$(D):
	$(Q)mkdir -p $(D)

$(I):
	$(Q)mkdir -p $(I)

mrproper:
	$(Q)rm -rvf $(O) $(I) $(D)
	$(Q)cd k3-image-gen && git clean -fdx

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
