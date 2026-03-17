# HDMI驱动

## 基本信息


```shell

# 列出所有 DRM 连接器及其状态
ls /sys/class/drm/

# 查看特定 HDMI 接口的状态 (通常是 card0-HDMI-A-1 或 card0-HDMI-A-2)
# 返回值: connected (已连接), disconnected (未连接), unknown
cat /sys/class/drm/card0-HDMI-A-1/status

# 查看当前连接的分辨率和刷新率信息
cat /sys/class/drm/card0-HDMI-A-1/modes

# 查看详细的 DRM 状态信息 (包含所有 connector, encoder, crtc)
cat /sys/kernel/debug/dri/0/state
# 或者
cat /sys/kernel/debug/dri/0/status

```

```shell

root@armbian:/sys/class/drm# ls /sys/class/drm
card0       card0-DP-2   card0-HDMI-A-1  card0-Writeback-1  renderD128  version
card0-DP-1  card0-DSI-1  card0-HDMI-A-2  card1              renderD129


```





































---