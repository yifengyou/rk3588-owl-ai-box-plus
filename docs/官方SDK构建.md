# 官方SDK构建

* <https://gitee.com/owlvisiontech/rk3588_linux_sdk_patch/wikis/1.%20sdk%20compile/3.%20%E7%BC%96%E8%AF%91%E7%8E%AF%E5%A2%83%E6%90%AD%E5%BB%BA>



建议使用Ubuntu20.04的操作系统进行开发以减少编译调试过程解决问题的时间成本，
建议在Ubuntu命令行中输入以下命令安装完整的软件依赖环境:

```shell

sudo apt install \
openssh-server \
android-tools-adb \
vim net-tools git \
cmake \
tree \
minicom \
gawk \
bison \
flex \
libssl-dev \
device-tree-compiler \
gcc-aarch64-linux-gnu mtools parted libudev-dev \
libusb-1.0-0-dev autoconf autotools-dev libsigsegv2 m4 intltool libdrm-dev curl sed \
make binutils build-essential gcc g++ bash patch gzip gawk bzip2 \
perl tar cpio python unzip rsync file bc wget libncurses5 u-boot-tools \
cvs mercurial rsync openssh-client subversion expect \
fakeroot liblz4-tool libtool keychain libncurses-dev texinfo -y
```

1. 完整编译命令说明参考sdk文件：
   docs/RK3588/Rockchip_RK3588_Quick_Start_Linux_CN.pdf

2. 使用例子：

```
source envsetup.sh
75. rockchip_rk356x_robot
76. rockchip_rk356x_robot_recovery
77. rockchip_rk3588
78. rockchip_rk3588_base
79. rockchip_rk3588_ipc
80. rockchip_rk3588_nvr
81. rockchip_rk3588_nvr_recovery
82. rockchip_rk3588_recovery
83. rockchip_rv1108_cvr
84. rockchip_rv1108_lock
    which would you like? [0]: 77

./build.sh lunch
processing option: lunch

You're building on Linux
Lunch menu...pick a combo:

default BoardConfig.mk
BoardConfig-nvr.mk
BoardConfig-rk3588-evb1-lp4-v10.mk
BoardConfig-rk3588-evb3-lp5-v10.mk
BoardConfig-rk3588s-evb1-lp4x-v10.mk
BoardConfig.mk
Which would you like? [0]: 2
switching to board: /home/eve/1_all_sdk/1_rk3588/device/rockchip/rk3588/BoardConfig-rk3588-evb1-lp4-v10.mk
./build.sh
```

编译成功后，生成固件目录：
输入图片说明

注意：

./build.sh编译过程中可能会遇到包下载失败导致的编译问题，多编译几次就好了。
或者下载如下网盘中的dl目录解压后拷贝到buildroot/dl目录，替换后再编译即可。


