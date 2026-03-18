# PCIE驱动

## RK3588 PCIE情况

![](./images/31563524273200.png)

![](./images/31574738737400.png)

![](./images/31591663980300.png)

![](./images/31599656428400.png)


## 6.6内核PCIE代码分析

```c
// drivers/pci/controller/dwc/pcie-dw-rockchip.c
static const struct dw_pcie_ops dw_pcie_ops = {
        .start_link = rk_pcie_establish_link,
        .stop_link = rk_pcie_stop_link,
        .link_up = rk_pcie_link_up,
};


```


## 4.4内核PCIE代码分析

```c
// drivers/pci/host/pcie-dw-rockchip.c
static int rk_pcie_establish_link(struct rk_pcie *rk_pcie)
{
    int retries;

    /* Rest the device */
    gpiod_set_value_cansleep(rk_pcie->rst_gpio, 0);
    msleep(100);
    gpiod_set_value_cansleep(rk_pcie->rst_gpio, 1);

    rk_pcie_disable_ltssm(rk_pcie);
    rk_pcie_link_status_clear(rk_pcie);
    /* Enable LTSSM */
    rk_pcie_enable_ltssm(rk_pcie);

    for (retries = 0; retries < 1000000; retries++) {
        if (rk_pcie_link_up(rk_pcie)) {
            dev_info(rk_pcie->dev, "PCIe Link up\n");
            return 0;
        }

        dev_info_ratelimited(rk_pcie->dev, "PCIe Linking...\n");
        mdelay(1);
    }

    dev_err(rk_pcie->dev, "PCIe Link Fail\n");

    return -EINVAL;
}

```


## 错误处理

## 驱动加载失败

![](./images/32047412612700.png)


### trainning失败

![](./images/31868244739600.png)


## trainning从0x1跳变到0x0，然后超时失败的问题

```text
PCIe 链路训练状态机（LTSSM）的逻辑如下：
0x0 (Detect): 主机发送探测信号，看有没有设备回应。
0x1 (Polling): 检测到设备后，进入此状态。主机和设备开始疯狂交换 TS1/TS2 有序集，目的是：
对齐极性（Polarity）
对齐位序（Lane Reversal）
协商速率（Gen1/Gen2/Gen3）
锁定符号边界
失败回退: 如果在规定时间内（通常几百毫秒）无法完成上述同步，或者误码率太高，LTSSM 判定训练失败，强制重置链路，回到 0x0 (Detect) 重新尝试。循环几次后彻底放弃。
结论：你的卡在“对话”刚开始就“吵崩了”或者“听不清对方说话”。
```

“0x1 -> 0x0” 的本质是：握手失败。

1. 大概率原因：你的 RK3588 试图以 Gen3 速率去训练那些只支持 Gen2 或者 信号质量较差 的卡，导致超时回退。
2. 最快解决方案：在设备树中强制指定 max-link-speed = <2>; (Gen2)。这通常能解决 80% 的此类兼容性问题。
3. 根本原因：如果是必须跑 Gen3 的卡却失败了，那就是你的 PCB 走线、转接板质量或连接器 存在信号完整性缺陷，需要硬件整改（加 Retimer 或重画板）。


RK3588 的 PCIe 控制器也是基于 DesignWare IP，且 Linux 6.6 对 RK3588 的支持也是较新的代码路径。

* 共性：两者都面临新驱动对信号质量要求变高、默认速率变快、电源管理变激进的问题。
* 特性：RK3588 支持 Gen3，默认会尝试 8GT/s，这对 PCB 走线和转接板的要求比 RK3399 (通常 Gen2) 更高。所以 RK3588 上“部分卡不认”的现象会更明显。

```text

pcie_aspm=off pci=noaer pcie_port_pm=off


```

* RK3588 的 PCIe 控制器在 Gen3 速率下对信号完整性（SI）要求极高。如果你的 PCB 走线稍长、有转接板、或者插槽接触电阻稍大，Gen3 的训练就会失败（LTSSM 卡在 Polling 0x1 然后回退 0x0）。而 4.4 内核可能默认没跑这么高，或者重试机制更宽容，所以能过
* max-link-speed 从 <0x03> (Gen3) 改为 <0x02> (Gen2)。这将大幅降低对信号质量的要求，让那些“挑剔”的卡也能正常握手

* Gen3 (8GT/s): 信号频率极高，对 PCB 损耗、反射、串扰非常敏感。需要完美的阻抗匹配（90Ω±10%）和较短的走线。任何微小的瑕疵（如廉价转接板、长排线、氧化触点）都会导致眼图闭合，训练失败。
* Gen2 (5GT/s): 频率降低了 37.5%，信号波长变长，对传输线效应的容忍度大幅提高。原本在 Gen3 下“看不清”的信号，在 Gen2 下变得“清晰可辨”。
兼容性: 如前所述，所有 PCIe 卡都支持 Gen2。牺牲一点理论带宽（从 ~3.9GB/s 降到 ~1.9GB/s），换取 100% 的卡都能识别，在嵌入式场景下是绝对值得的。

解决方式：

1. 第一步：加启动参数 ```pcie_aspm=off pci=noaer```。重启测试。
2. 第二步：如果不行，改 DTS 加 ```max-link-speed = <2>``` (强制 Gen2)。重启测试。
3. 第三步：如果还不行，尝试 max-link-speed = <1> (强制 Gen1)。




## 附录

### 附录一： LTSSM状态机

![](./images/32005862227700.png)

![](./images/32013175805100.png)



---