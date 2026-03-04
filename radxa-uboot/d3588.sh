#!/bin/bash

set -e

tool=$(which aarch64-linux-gnu-gcc)
export CROSS_COMPILE_ARM64="${tool%gcc}"
echo "using gcc: [${CROSS_COMPILE_ARM64}]"

rm -rf spl/u-boot-spl*

# Start building (U-Boot, SPL, etc.)
make CROSS_COMPILE=${CROSS_COMPILE_ARM64} liontron-d3588_defconfig
make CROSS_COMPILE=${CROSS_COMPILE_ARM64} -j`nproc`

# Call the official build.
./make.sh rk3588

ls -alh fit/uboot.itb

cp -a fit/uboot.itb uboot.img
ls -alh uboot.img
md5sum uboot.img

echo "All done!"

