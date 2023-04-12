# Introduction

This is a trivial build package to help ease build and deploy of various K3
Boards with as much upstream components as possible.

# Upstream Status

* U-boot: Upstream
* trusted-firmware-cortex-a: Upstream (used to be called arm-trusted-firmware
* OPTEE OS: Upstream
* k3-image-gen: TI, but hopefully binman should be able to replace this.
* ti-linux-firmware: TI, but hopefully we should upstream the firmware pieces as well.

# System pre-requisites:
The following lists the pre-requisites for building the bootloader components

* This assumes a x86_64 Linux system for build. if not, Adjust appropriately.

## Compiler

https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads

Download the following:
* AArch32 GNU/Linux target with hard float (arm-none-linux-gnueabihf)
* AArch64 GNU/Linux target (aarch64-none-linux-gnu)

Also see: https://www.linaro.org/downloads/#gnu_and_llvm You could
optionally use https://snapshots.linaro.org/gnu-toolchain/, but
`CROSS_COMPILE_64` and `CROSS_COMPILE_32` variables need to be
adjusted accordingly.

## Host package dependencies

* Optee: https://optee.readthedocs.io/en/latest/building/prerequisites.html
* U-boot: https://github.com/u-boot/u-boot/blob/master/tools/docker/Dockerfile#L35 https://github.com/u-boot/u-boot/blob/master/tools/binman/binman.rst
* TFA: https://github.com/ARM-software/arm-trusted-firmware/blob/master/docs/requirements.txt https://github.com/ARM-software/arm-trusted-firmware/blob/master/docs/getting_started/prerequisites.rst

If getting it all correctly seems painful, unfortunately, it is.. (also see TODO)

# Build steps

## Cloning the environment

If you want the latest:
```
git clone https://github.com/nmenon/k3-upstream-boot-build.git
```
OR a specific branch:
```
git clone -b some-branch https://github.com/nmenon/k3-upstream-boot-build.git
```

## Update the gitsubmodules

To help ease syncing there is a makefile rule to make this happen:
```
cd k3-upstream-boot-build
make gitsync
```

## Checking what board to build
Look for the various board and bootmodes supported

```
ls configs
```

Convention followed is: ```<soc>_<board>_<security_type>_<bootmode>_defconfig``` where

* SoC is one of various SoC types - j721e, am64 etc.
* Board is one of the supported boards
* security type is one of gp (non-secure), hsfs (auth for ti key), hsse (customer/device-specific key fused)
* bootmode is various supported bootmodes for the Board

## Building the platform

```
make mysoc_myboard_gp_mmc_defconfig
make
```

## Bootfiles

boot files will be located in deploy/ folder.

# Making all platforms

The MAKEALL script is a helper to help build all the platforms in one single shot

```
./MAKEALL
```
Or for a specific defconfig:
```
./MAKEALL am64x_evm_gp_all_defconfig
```

# Internal details of config file

## Various boot configuration

There are few combinations of Boot image organization involved here:

* Multi-certificate Boot: The ROM bootloader is capable of loading
  more than one firmware binary. In this mode, the X509 certificate
  (tiboot3.bin) contains not just the secondary bootloader binary, but also
  the tifs firmware binary. In the "legacy" boot, just the R5 secondary
  bootloader(SBL) is loaded. With multi-certificate capability, the ROM
  is capable of loading R5 bootloader (SBL), and in addition load the tifs
  firmware along with it's configuration data to allow both R5 and TIFS firmware
  to initialize in parallel (speeding up the boot process). This is indicated
  by the `MULTICERTIFICATE_BOOT_CAPABLE` variable in the config files
* TIFS Split image: The orginal DMSC firmware had security, power and device
  management functionality all rolled into a single firmware image. However,
  with newer and more massive devices, it was clear that a limited land-locked
  SRAM is in-capable of scaling to various Processor sizing requirements since
  the data and feature support variations were massive. To better support this,
  newer SoCs run the TIFS (Security function) only on the TIFS core and the
  device management and power management function is run on the boot R5. This
  is indicated by the `DM_COMBINED_WITH_TIFS` variable in the config files.

The following table provides a bird's eye view of the same
| SoC     | Multicertificate Boot | DM and TIFS combined |
| :---    |            :---:      |            :---:     |
| AM65x   |           No          |           Yes        |
| J721E   |           No          |           No         |
| AM64x   |           Yes         |           Yes        |
| J7200   |           Yes         |           No         |
| AM62X   |           Yes         |           No         |
| AM62AX  |           Yes         |           No         |
| J721S2  |           Yes         |           No         |

## Various variables

| Variable name         | Description |
| :---                  | :---        |
| SOC_NAME   | SoC name of the board |
| BOARD_NAME   | Name of the board |
| SECURITY_TYPE   | What kind of security type is the chip? hs/gp |
| MULTICERTIFICATE_BOOT_CAPABLE | Is this multi-certificate boot capable chip: 0 or 1|
| DM_COMBINED_WITH_TIFS | Is DM combined with TIFS in the firmware? 0 or 1|
| K3IMGGEN_SOC | (hopefully gone soon) what name does k3imagegen use for this SoC?|
| FW_TIFS_PATH | path to tifs firmware |
| FW_DM_PATH | (valid only if not combined image) Path to the dm firmware |
| TFA_BOARD | What is the board name used in Trusted-firmware cortex-a? |
| TFA_EXTRA_ARGS | Any extra TFA arguments to pass to build (example: K3_PM_SYSTEM_SUSPEND=1) |
| OPTEE_PLATFORM | Name of the optee platform |
| OPTEE_EXTRA_ARGS | Any extra OPTEE arguments to pass to build (example:CFG_CONSOLE_UART=0x8) |
| UBOOT_ARMV7_DEFCONFIG | Name of the u-boot defconfig for the R5 SPL |
| UBOOT_ARMV8_DEFCONFIG | Name of the u-boot defconfig for the armv8 processor |

# FUTURE TODOs

* Create a docker container for building the packages
* Add more platform configurations
