# PCIE驱动


## 6.6内核

```c
// drivers/pci/controller/dwc/pcie-dw-rockchip.c
static const struct dw_pcie_ops dw_pcie_ops = {
        .start_link = rk_pcie_establish_link,
        .stop_link = rk_pcie_stop_link,
        .link_up = rk_pcie_link_up,
};


```


## 4.4内核

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






---