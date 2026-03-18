# USB驱动

## 常见问题

### USB接口无法使用问题

方法一：命令方式

```shell
串口一行一行输入：
echo 54 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio54/direction
echo 1 > /sys/class/gpio/gpio54/value

```

方法二：修改dts编译内核后烧录kernel目录下 zboot.img

dts中添加：如下usb供电配置

```shell
vbus5v_pwr: vbus5v-pwr {
    compatible = "regulator-fixed";
    regulator-name = "vbus5v_pwr";
    gpio = <&gpio1 RK_PC6 GPIO_ACTIVE_HIGH>;
    enable-active-high;
    regulator-always-on;
    regulator-boot-on;
    regulator-min-microvolt = <5000000>;
    regulator-max-microvolt = <5000000>;
};
```

### otg口adb不能使用

原因：otg口用的HUSB311 芯片，需要修改dts来解决：
修改方法：将dts中如下部分：

```text
usbc0: fusb302@22 {
compatible = "fcs,fusb302";
reg = <0x22>;
```

改为如下编译即可。

```text
usbc0: husb311@4e {
compatible = "hynetek,husb311";
reg = <0x4e>;
```

按如上修改好后，执行./build.sh kernel来编译kernel，并在板子中烧录kernel目录下zboot.img即可。

