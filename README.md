# Introduction

This is a build package to help ease build and deploy of various K3
Boards.  By default, as many upstream components as possible are used.
A different repository location for either U-Boot, Arm Trusted Firmware, or
OP-TEE can be specified if desired.

# Upstream Status

* U-boot: Upstream
* Trusted-Firmware-A: Upstream (used to be called Arm-Trusted-Firmware)
* OPTEE OS: Upstream
* ti-linux-firmware: TI, but hopefully we should upstream the firmware pieces as well.

![build status](https://github.com/nmenon/k3-upstream-boot-build/actions/workflows/main.yml/badge.svg)

# System pre-requisites:
The following lists the pre-requisites for building the bootloader components

* This assumes a x86_64 Linux system for build. If not, adjust appropriately.

## Compiler

Download the following:
* AArch32 GNU/Linux target with hard float (arm-none-linux-gnueabihf)
* AArch64 GNU/Linux target (aarch64-none-linux-gnu)

### Ubuntu
Ubuntu provides ARM cross compiler packages.  To use, install with:

    apt install gcc-aarch64-linux-gnu gcc-arm-none-eabi

and set your cross compiler env variables:

    export CROSS_COMPILE_64=aarch64-linux-gnu-

    export CROSS_COMPILE_32=arm-none-eabi-

### Directly from arm.com
https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads

Also see: https://www.linaro.org/downloads/#gnu_and_llvm You could
optionally use https://snapshots.linaro.org/gnu-toolchain/, but
`CROSS_COMPILE_64` and `CROSS_COMPILE_32` variables need to be
adjusted accordingly.

## Host package dependencies

* OPTEE: https://optee.readthedocs.io/en/latest/building/prerequisites.html
* U-Boot: https://github.com/u-boot/u-boot/blob/master/tools/docker/Dockerfile#L35 https://github.com/u-boot/u-boot/blob/master/tools/binman/binman.rst
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
* Security type is one of gp (non-secure), hsfs (auth for ti key), hsse (customer/device-specific key fused)
* Bootmode is various supported bootmodes for the board

## Building the platform

```
make mysoc_myboard_gp_mmc_defconfig
make
```

### Building an SD card image

The K3 ROM when booting from an SD card in filesystem boot mode can be very
particular about the format it expects. To ease generation of a working
SD card this tool can provide an simple SD card image.

To build an SD card image your host system will need mtools, parted, and
dosfstools installed:

```
sudo apt install mtools parted dosfstools
```

After selecting your platform defconfig as above, use the `sdcard` target:

```
make sdcard
```

The resulting SD card will be located at `deploy/sdcard.img` and can
be written directly to an SD card. For instance using dd:

```
dd if=deploy/sdcard.img of=/dev/sd<card>
```

Note: This SD card does not contain an OS. U-Boot will attempt to load
the OS from media as specified by U-Boot stdboot. One can add a uEnv.txt
file to the SD card boot partition to further direct the boot process.

### To override a repository location
To use a different repository location for U-Boot, Arm Trusted Firmware,
OP-TEE, or ti-linux-firmware define the appropriate variables below

| Repo | Location variable |
| :--- | :--- |
| arm trusted firmware | TFA_DIR |
| optee OS | OPTEE_DIR |
| U-Boot | UBOOT_DIR |
| ti-linux-firmware | FW_DIR |

For example, to use the TI SDK repo for u-boot, use:

```
make mysoc_myboard_gp_mmc_defconfig
make UBOOT_DIR=<path to ti-u-boot>
```

## Output files

* Intermediate build artifacts will be located in build/
* Boot files will be located in deploy/ (copy these to your SD card)

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

## Various variables

| Variable name         | Description |
| :---                  | :---        |
| SOC_NAME   | SoC name of the board |
| BOARD_NAME   | Name of the board |
| SECURITY_TYPE   | What kind of security type is the chip? (gp, hs-fs, hs) |
| TFA_BOARD | What is the board name used in Trusted-firmware cortex-a? |
| TFA_EXTRA_ARGS | Any extra TFA arguments to pass to build (example: K3_PM_SYSTEM_SUSPEND=1) |
| OPTEE_PLATFORM | Name of the optee platform |
| OPTEE_EXTRA_ARGS | Any extra OPTEE arguments to pass to build (example:CFG_CONSOLE_UART=0x8) |
| UBOOT_ARMV7_DEFCONFIG | Name of the u-boot defconfig for the R5 SPL |
| UBOOT_ARMV8_DEFCONFIG | Name of the u-boot defconfig for the armv8 processor |

# FUTURE TODOs

* Create a docker container for building the packages
* Add more platform configurations
