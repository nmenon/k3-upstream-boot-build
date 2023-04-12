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

## Checking what board to build
Look for the various board and bootmodes supported

```
ls configs
```

Convention followed is: **<soc>_<security_type>_<board>_<bootmode>_defconfig** where

* SoC is one of various SoC types - j721e, am64 etc.
* security type is one of gp (non-secure), hsfs (auth for ti key), hsse (customer/device-specific key fused)
* Board is one of the supported boards
* bootmode is various supported bootmodes for the Board

## Building the platform

```
make mysoc_gp_myboard_mmc_defconfig
make
```

## Bootfiles

boot files will be located in deploy/ folder.

# FUTURE TODOs

* Create a docker container for building the packages
