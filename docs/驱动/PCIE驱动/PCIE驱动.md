# PCIE驱动

## RK3588 PCIE情况

![](./images/31563524273200.png)

![](./images/31574738737400.png)

![](./images/31591663980300.png)

![](./images/31599656428400.png)


## 6.6内核PCIE代码分析

pcie-dw-rockchip.ko 可以单独构建成ko，然后修改代码验证测试，无需重构内核


### pcie-dw-rockchip入口

```c
// rockchip-linux_kernel.git/drivers/pci/controller/dwc/pcie-dw-rockchip.c

static struct platform_driver rk_plat_pcie_driver = {
	.driver = {
		.name	= "rk-pcie",
		.of_match_table = rk_pcie_of_match,
		.pm = &rockchip_dw_pcie_pm_ops, // 电源管理操作集（dev_pm_ops 结构体）的指针
	},
	.probe = rk_pcie_probe, // 当内核发现设备树中的节点与该驱动匹配成功后立即调用
	.remove = rk_pcie_remove,
	.shutdown = rk_pcie_shutdown,
};

module_platform_driver(rk_plat_pcie_driver);

MODULE_AUTHOR("Simon Xue <xxm@rock-chips.com>");
MODULE_DESCRIPTION("RockChip PCIe Controller driver");
MODULE_LICENSE("GPL v2");
```

### of兼容性列表

rk3588针对pcie的compatible字段如下：

```text
pcie@fe150000 {
    compatible = "rockchip,rk3588-pcie snps,dw-pcie";
```

of驱动匹配 rockchip,rk3588-pcie

```c
static const struct of_device_id rk_pcie_of_match[] = {
	{
		.compatible = "rockchip,rk3528-pcie",
		.data = &rk3528_pcie_rc_of_data,
	},
	{
		.compatible = "rockchip,rk3562-pcie",
		.data = &rk3528_pcie_rc_of_data,
	},
	{
		.compatible = "rockchip,rk3568-pcie",
		.data = NULL,
	},
	{
		.compatible = "rockchip,rk3576-pcie",
		.data = &rk3528_pcie_rc_of_data,
	},
	{
		.compatible = "rockchip,rk3588-pcie",
		.data = NULL,
	},
	{},
};
```

### 电源管理

```c
static const struct dev_pm_ops rockchip_dw_pcie_pm_ops = {
#ifdef CONFIG_PCIEASPM
	.prepare = rockchip_dw_pcie_prepare,
	.complete = rockchip_dw_pcie_complete,
#endif
	SET_NOIRQ_SYSTEM_SLEEP_PM_OPS(rockchip_dw_pcie_suspend,
				      rockchip_dw_pcie_resume)
};

```

### probe加载函数


当前内核配置pcie在线程中初始化

```shell
# grep -i CONFIG_PCIE_RK_THREADED_INIT .config
CONFIG_PCIE_RK_THREADED_INIT=y
```


```c
static int rk_pcie_probe(struct platform_device *pdev)
{
	if (IS_ENABLED(CONFIG_PCIE_RK_THREADED_INIT)) {
		struct task_struct *tsk;

		tsk = kthread_run(rk_pcie_really_probe, pdev, "rk-pcie");
		if (IS_ERR(tsk))
			return dev_err_probe(&pdev->dev, PTR_ERR(tsk), "start rk-pcie thread failed\n");

		return 0;
	}

	return rk_pcie_really_probe(pdev);
}
```

### rk_pcie_really_probe初始化

```c
static int rk_pcie_really_probe(void *p)
{
	struct platform_device *pdev = p;
	struct device *dev = &pdev->dev;
	struct rk_pcie *rk_pcie = NULL;
	struct dw_pcie *pci;
	int ret;
	const struct of_device_id *match;
	const struct rk_pcie_of_data *data;

	/* 1. resource initialization */
	match = of_match_device(rk_pcie_of_match, dev);
	if (!match) {
		ret = -EINVAL;
		goto release_driver;
	}

	data = (struct rk_pcie_of_data *)match->data;

	rk_pcie = devm_kzalloc(dev, sizeof(*rk_pcie), GFP_KERNEL);
	if (!rk_pcie) {
		ret = -ENOMEM;
		goto release_driver;
	}

	pci = devm_kzalloc(dev, sizeof(*pci), GFP_KERNEL);
	if (!pci) {
		ret = -ENOMEM;
		goto release_driver;
	}

	/* 2. variables assignment */
	rk_pcie->pci = pci;
	rk_pcie->msi_vector_num = data ? data->msi_vector_num : 0;
	rk_pcie->intx = 0xffffffff;
	pci->dev = dev;
	pci->ops = &dw_pcie_ops; // 操作函数
	platform_set_drvdata(pdev, rk_pcie);

	/* 3. firmware resource */
	ret = rk_pcie_resource_get(pdev, rk_pcie);
	if (ret) {
		dev_err_probe(dev, ret, "resource init failed\n");
		goto release_driver;
	}

	/* 4. hardware io settings */
	ret = rk_pcie_hardware_io_config(rk_pcie);
	if (ret) {
		dev_err_probe(dev, ret, "setting hardware io failed\n");
		goto release_driver;
	}

	pm_runtime_enable(dev);
	pm_runtime_get_sync(pci->dev);

	/* 5. host registers manipulation */
	ret = rk_pcie_host_config(rk_pcie);
	if (ret) {
		dev_err_probe(dev, ret, "host registers manipulation failed\n");
		goto unconfig_hardware_io;
	}

	/* 6. software process */
	ret = rk_pcie_init_irq_and_wq(rk_pcie, pdev);
	if (ret)
		goto unconfig_host;

	ret = rk_add_pcie_port(rk_pcie, pdev);

	if (rk_pcie->is_signal_test == true)
		return 0;

	if (ret && !rk_pcie->slot_pluggable)
		goto deinit_irq_and_wq;

	if (rk_pcie->slot_pluggable) {
		rk_pcie->hp_slot.plat_ops = &rk_pcie_gpio_hp_plat_ops;
		rk_pcie->hp_slot.np = rk_pcie->pci->dev->of_node;
		rk_pcie->hp_slot.slot_nr = rk_pcie->pci->pp.bridge->busnr;
		rk_pcie->hp_slot.pdev = pci_get_slot(rk_pcie->pci->pp.bridge->bus, PCI_DEVFN(0, 0));

		ret = register_gpio_hotplug_slot(&rk_pcie->hp_slot);
		if (ret < 0)
			dev_warn(dev, "Failed to register ops for GPIO Hot-Plug controller: %d\n",
				 ret);
		/* Set debounce to 200ms for safe if possible */
		gpiod_set_debounce(rk_pcie->hp_slot.gpiod, 200);
	}

	ret = rk_pcie_init_dma_trx(rk_pcie);
	if (ret) {
		dev_err_probe(dev, ret, "failed to add dma extension\n");
		goto deinit_irq_and_wq;
	}

	ret = rockchip_pcie_debugfs_init(rk_pcie);
	if (ret < 0)
		dev_err_probe(dev, ret, "failed to setup debugfs\n");

	dw_pcie_dbi_ro_wr_dis(pci);

	/* 7. framework misc settings */
	device_init_wakeup(dev, true);
	device_enable_async_suspend(dev); /* Enable async system PM for multiports SoC */
	rk_pcie->finish_probe = true;

	return 0;

deinit_irq_and_wq:
	destroy_workqueue(rk_pcie->hot_rst_wq);
	if (rk_pcie->irq_domain)
		irq_domain_remove(rk_pcie->irq_domain);
unconfig_host:
	rk_pcie_host_unconfig(rk_pcie);
unconfig_hardware_io:
	pm_runtime_put(dev);
	pm_runtime_disable(dev);
	rk_pcie_hardware_io_unconfig(rk_pcie);
release_driver:
	if (rk_pcie)
		rk_pcie->finish_probe = true;
	if (IS_ENABLED(CONFIG_PCIE_RK_THREADED_INIT))
		device_release_driver(dev);

	return ret;
}
```

### dw_pcie_ops操作集合

在probe的时候，注册操作集合

```c
// pci->ops = &dw_pcie_ops;

static const struct dw_pcie_ops dw_pcie_ops = {
	.start_link = rk_pcie_establish_link,
	.stop_link = rk_pcie_stop_link,
	.link_up = rk_pcie_link_up,
};
```


### rk_pcie_establish_link建立连接

```c

static int rk_pcie_establish_link(struct dw_pcie *pci)
{
	int retries, power;
	struct rk_pcie *rk_pcie = to_rk_pcie(pci);
	int hw_retries = 0;
	u32 ltssm;

	/*
	 * For standard RC, even if the link has been setup by firmware,
	 * we still need to reset link as we need to remove all resource info
	 * from devices, for instance BAR, as it wasn't assigned by kernel.
	 */
	if (dw_pcie_link_up(pci) && !rk_pcie->hp_no_link) {
		dev_err(pci->dev, "link is already up\n");
		return 0;
	}

	for (hw_retries = 0; hw_retries < RK_PCIE_ENUM_HW_RETRYIES; hw_retries++) {
		/* Rest the device */
		gpiod_set_value_cansleep(rk_pcie->rst_gpio, 0);

		rk_pcie_disable_ltssm(rk_pcie);
		rk_pcie_link_status_clear(rk_pcie);
		rk_pcie_enable_debug(rk_pcie);

		/* Enable client reset or link down interrupt */
		rk_pcie_writel_apb(rk_pcie, PCIE_CLIENT_INTR_MASK, 0x40000);

		/* Enable LTSSM */
		rk_pcie_enable_ltssm(rk_pcie);

		/*
		 * In resume routine, function devices' resume function must be late after
		 * controllers'. Some devices, such as Wi-Fi, need special IO setting before
		 * finishing training. So there must be timeout here. These kinds of devices
		 * need rescan devices by its driver when used. So no need to waste time waiting
		 * for training pass.
		 *
		 * PCIe requires the refclk to be stable for 100µs prior to releasing
		 * PERST and T_PVPERL (Power stable to PERST# inactive) should be a
		 * minimum of 100ms.  See table 2-4 in section 2.6.2 AC, the PCI Express
		 * Card Electromechanical Specification 3.0. So 100ms in total is the min
		 * requuirement here. We add a 200ms by default for sake of hoping everthings
		 * work fine. If it doesn't, please add more in DT node by add rockchip,perst-inactive-ms.
		 */
		if (rk_pcie->in_suspend && rk_pcie->skip_scan_in_resume) {
			rfkill_get_wifi_power_state(&power);
			if (!power) {
				gpiod_set_value_cansleep(rk_pcie->rst_gpio, 1);
				return 0;
			}
			if (rk_pcie->s2r_perst_inactive_ms)
				usleep_range(rk_pcie->s2r_perst_inactive_ms * 1000,
					(rk_pcie->s2r_perst_inactive_ms + 1) * 1000);
		} else {
			usleep_range(rk_pcie->perst_inactive_ms * 1000,
				(rk_pcie->perst_inactive_ms + 1) * 1000);
		}

		gpiod_set_value_cansleep(rk_pcie->rst_gpio, 1);

		/*
		 * Add this delay because we observe devices need a period of time to be able to
		 * work, so the link is always up stably after it. And the default 1ms could help us
		 * save 20ms for scanning devices. If the devices need longer than 2s to be able to
		 * work, please change wait_for_link_ms via dts.
		 */
		usleep_range(1000, 1100);

		for (retries = 0; retries < rk_pcie->wait_for_link_ms / 20; retries++) {
			if (dw_pcie_link_up(pci)) {
				/*
				 * We may be here in case of L0 in Gen1. But if EP is capable
				 * of Gen2 or Gen3, Gen switch may happen just in this time, but
				 * we keep on accessing devices in unstable link status. Given
				 * that LTSSM max timeout is 24ms per period, we can wait a bit
				 * more for Gen switch.
				 */
				msleep(50);
				/* In case link drop after linkup, double check it */
				if (dw_pcie_link_up(pci)) {
					dev_info(pci->dev, "PCIe Link up, LTSSM is 0x%x\n",
						rk_pcie_readl_apb(rk_pcie, PCIE_CLIENT_LTSSM_STATUS));
					rk_pcie_debug_dump(rk_pcie);
					if (rk_pcie->slot_pluggable)
						rk_pcie->hp_no_link = false;
					return 0;
				}
			}

			dev_info_ratelimited(pci->dev, "PCIe Linking... LTSSM is 0x%x\n",
					rk_pcie_readl_apb(rk_pcie, PCIE_CLIENT_LTSSM_STATUS));
			rk_pcie_debug_dump(rk_pcie);
			usleep_range(20000, 21000);
		}

		/*
		 * In response to the situation where PCIe peripherals cannot be
		 * enumerated due tosignal abnormalities, reset PERST# and reset
		 * the peripheral power supply, then restart the enumeration.
		 */
		ltssm = rk_pcie_readl_apb(rk_pcie, PCIE_CLIENT_LTSSM_STATUS);
		dev_err(pci->dev, "PCIe Link Fail, LTSSM is 0x%x, hw_retries=%d\n", ltssm, hw_retries);
		if (ltssm >= 3 && !rk_pcie->is_signal_test) {
			rk_pcie_disable_power(rk_pcie);
			msleep(1000);
			rk_pcie_enable_power(rk_pcie);
		} else {
			break;
		}
	}

	if (rk_pcie->slot_pluggable) {
		rk_pcie->hp_no_link = true;
		return 0;
	} else {
		return rk_pcie->is_signal_test == true ? 0 : -EINVAL;
	}
}

```

错误日志：

```shell
root@armbian:~# dmesg |grep fe15000
[ 4459.002093] rk-pcie fe150000.pcie: invalid prsnt-gpios property in node
[ 4459.018998] rk-pcie fe150000.pcie: can't get current limit.
[ 4459.019679] rk-pcie fe150000.pcie: host bridge /pcie@fe150000 ranges:
[ 4459.019747] rk-pcie fe150000.pcie:       IO 0x00f0100000..0x00f01fffff -> 0x00f0100000
[ 4459.019794] rk-pcie fe150000.pcie:      MEM 0x00f0200000..0x00f0ffffff -> 0x00f0200000
[ 4459.019829] rk-pcie fe150000.pcie:      MEM 0x0900000000..0x093fffffff -> 0x0900000000
[ 4459.019929] rk-pcie fe150000.pcie: iATU: unroll T, 8 ob, 8 ib, align 64K, limit 8G
[ 4459.222285] rk-pcie fe150000.pcie: PCIe Linking... LTSSM is 0x0
[ 4459.243493] rk-pcie fe150000.pcie: PCIe Linking... LTSSM is 0x0
[ 4459.264736] rk-pcie fe150000.pcie: PCIe Linking... LTSSM is 0x1
[ 4459.285962] rk-pcie fe150000.pcie: PCIe Linking... LTSSM is 0x0
[ 4459.307170] rk-pcie fe150000.pcie: PCIe Linking... LTSSM is 0x0
[ 4461.340174] rk-pcie fe150000.pcie: PCIe Link Fail, LTSSM is 0x0, hw_retries=0
[ 4461.340238] rk-pcie fe150000.pcie: failed to initialize host
```








## 4.4内核PCIE代码分析


```c
// drivers/pci/controller/dwc/pcie-dw-rockchip.c
static const struct dw_pcie_ops dw_pcie_ops = {
        .start_link = rk_pcie_establish_link,
        .stop_link = rk_pcie_stop_link,
        .link_up = rk_pcie_link_up,
};


```


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


调试方法，将pcie rockchip代码构建为M（module）

![](./images/39415794730000.png)
















## 附录

### 附录一： LTSSM状态机

![](./images/32005862227700.png)

![](./images/32013175805100.png)


### 测试卡：nvme转接卡

```text

root@armbian:~# lspci -vvv -s 0000:01:00.0
0000:01:00.0 Non-Volatile memory controller: MAXIO Technology (Hangzhou) Ltd. NVMe SSD Controller MAP1202 (DRAM-less) (rev 01) (prog-if 02 [NVM Express])
	Subsystem: MAXIO Technology (Hangzhou) Ltd. NVMe SSD Controller MAP1202 (DRAM-less)
	Control: I/O- Mem+ BusMaster+ SpecCycle- MemWINV- VGASnoop- ParErr- Stepping- SERR- FastB2B- DisINTx+
	Status: Cap+ 66MHz- UDF- FastB2B- ParErr- DEVSEL=fast >TAbort- <TAbort- <MAbort- >SERR- <PERR- INTx-
	Latency: 0
	Interrupt: pin A routed to IRQ 48
	IOMMU group: 6
	Region 0: Memory at f0200000 (64-bit, non-prefetchable) [size=16K]
	Capabilities: [40] Power Management version 3
		Flags: PMEClk- DSI- D1- D2- AuxCurrent=0mA PME(D0+,D1-,D2-,D3hot+,D3cold+)
		Status: D0 NoSoftRst+ PME-Enable- DSel=0 DScale=0 PME-
	Capabilities: [50] MSI: Enable- Count=1/32 Maskable+ 64bit+
		Address: 0000000000000000  Data: 0000
		Masking: 00000000  Pending: 00000000
	Capabilities: [70] Express (v2) Endpoint, IntMsgNum 31
		DevCap:	MaxPayload 512 bytes, PhantFunc 0, Latency L0s unlimited, L1 unlimited
			ExtTag- AttnBtn- AttnInd- PwrInd- RBE+ FLReset+ SlotPowerLimit 0W TEE-IO-
		DevCtl:	CorrErr+ NonFatalErr+ FatalErr+ UnsupReq+
			RlxdOrd+ ExtTag- PhantFunc- AuxPwr- NoSnoop+ FLReset-
			MaxPayload 256 bytes, MaxReadReq 512 bytes
		DevSta:	CorrErr- NonFatalErr- FatalErr- UnsupReq- AuxPwr+ TransPend-
		LnkCap:	Port #0, Speed 8GT/s, Width x4, ASPM L1, Exit Latency L1 <64us
			ClockPM- Surprise- LLActRep- BwNot- ASPMOptComp+
		LnkCtl:	ASPM L1 Enabled; RCB 64 bytes, LnkDisable- CommClk+
			ExtSynch- ClockPM- AutWidDis- BWInt- AutBWInt-
		LnkSta:	Speed 8GT/s, Width x4
			TrErr- Train- SlotClk+ DLActive- BWMgmt- ABWMgmt-
		DevCap2: Completion Timeout: Range ABCD, TimeoutDis+ NROPrPrP- LTR+
			 10BitTagComp- 10BitTagReq- OBFF Via message, ExtFmt- EETLPPrefix-
			 EmergencyPowerReduction Not Supported, EmergencyPowerReductionInit-
			 FRS- TPHComp- ExtTPHComp-
			 AtomicOpsCap: 32bit- 64bit- 128bitCAS-
		DevCtl2: Completion Timeout: 16ms to 55ms, TimeoutDis-
			 AtomicOpsCtl: ReqEn-
			 IDOReq- IDOCompl- LTR+ EmergencyPowerReductionReq-
			 10BitTagReq- OBFF Disabled, EETLPPrefixBlk-
		LnkCap2: Supported Link Speeds: 2.5-8GT/s, Crosslink- Retimer- 2Retimers- DRS-
		LnkCtl2: Target Link Speed: 8GT/s, EnterCompliance- SpeedDis-
			 Transmit Margin: Normal Operating Range, EnterModifiedCompliance- ComplianceSOS-
			 Compliance Preset/De-emphasis: -6dB de-emphasis, 0dB preshoot
		LnkSta2: Current De-emphasis Level: -6dB, EqualizationComplete+ EqualizationPhase1+
			 EqualizationPhase2+ EqualizationPhase3+ LinkEqualizationRequest-
			 Retimer- 2Retimers- CrosslinkRes: unsupported
	Capabilities: [b0] MSI-X: Enable+ Count=9 Masked-
		Vector table: BAR=0 offset=00003000
		PBA: BAR=0 offset=00002000
	Capabilities: [100 v2] Advanced Error Reporting
		UESta:	DLP- SDES- TLP- FCP- CmpltTO- CmpltAbrt- UnxCmplt- RxOF- MalfTLP-
			ECRC- UnsupReq- ACSViol- UncorrIntErr- BlockedTLP- AtomicOpBlocked- TLPBlockedErr-
			PoisonTLPBlocked- DMWrReqBlocked- IDECheck- MisIDETLP- PCRC_CHECK- TLPXlatBlocked-
		UEMsk:	DLP- SDES- TLP- FCP- CmpltTO- CmpltAbrt- UnxCmplt- RxOF- MalfTLP-
			ECRC- UnsupReq- ACSViol- UncorrIntErr+ BlockedTLP- AtomicOpBlocked- TLPBlockedErr-
			PoisonTLPBlocked- DMWrReqBlocked- IDECheck- MisIDETLP- PCRC_CHECK- TLPXlatBlocked-
		UESvrt:	DLP+ SDES+ TLP- FCP+ CmpltTO- CmpltAbrt- UnxCmplt- RxOF+ MalfTLP+
			ECRC- UnsupReq- ACSViol- UncorrIntErr+ BlockedTLP- AtomicOpBlocked- TLPBlockedErr-
			PoisonTLPBlocked- DMWrReqBlocked- IDECheck- MisIDETLP- PCRC_CHECK- TLPXlatBlocked-
		CESta:	RxErr- BadTLP- BadDLLP- Rollover- Timeout- AdvNonFatalErr- CorrIntErr- HeaderOF-
		CEMsk:	RxErr- BadTLP- BadDLLP- Rollover- Timeout- AdvNonFatalErr+ CorrIntErr+ HeaderOF+
		AERCap:	First Error Pointer: 00, ECRCGenCap+ ECRCGenEn- ECRCChkCap+ ECRCChkEn-
			MultHdrRecCap- MultHdrRecEn- TLPPfxPres- HdrLogCap-
		HeaderLog: 00000000 00000000 00000000 00000000
	Capabilities: [148 v1] Device Serial Number 00-00-00-00-00-00-00-00
	Capabilities: [158 v1] Alternative Routing-ID Interpretation (ARI)
		ARICap:	MFVC- ACS+, Next Function: 0
		ARICtl:	MFVC- ACS-, Function Group: 0
	Capabilities: [168 v1] Secondary PCI Express
		LnkCtl3: LnkEquIntrruptEn- PerformEqu-
		LaneErrStat: 0
	Capabilities: [1d4 v1] Latency Tolerance Reporting
		Max snoop latency: 0ns
		Max no snoop latency: 0ns
	Capabilities: [1dc v1] L1 PM Substates
		L1SubCap: PCI-PM_L1.2+ PCI-PM_L1.1+ ASPM_L1.2+ ASPM_L1.1+ L1_PM_Substates+
			  PortCommonModeRestoreTime=10us PortTPowerOnTime=1000us
		L1SubCtl1: PCI-PM_L1.2- PCI-PM_L1.1- ASPM_L1.2- ASPM_L1.1-
			   T_CommonMode=0us LTR1.2_Threshold=1016832ns
		L1SubCtl2: T_PwrOn=1000us
	Capabilities: [1ec v1] Vendor Specific Information: ID=0002 Rev=4 Len=100 <?>
	Capabilities: [2ec v1] Vendor Specific Information: ID=0001 Rev=1 Len=038 <?>
	Kernel driver in use: nvme
	Kernel modules: nvme

```























---