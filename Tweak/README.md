# 泡泡悬浮摇杆（RootHide）

## 构建安装

需要 macOS、Theos、RootHide Bootstrap 工具链和可访问设备的 SSH。此版本同时支持 AppsDump3 4.0.x 的系统模拟定位。

```sh
cd Tweak
make package FINALPACKAGE=1
make install
```

也可以把 `packages/` 下生成的 RootHide DEB 传到设备后，用 Sileo 安装并重启 SpringBoard。

## 使用

1. 在 Location Spoofer 中选择“本地 Wi-Fi 代理”并开启虚拟定位。
2. 切换到目标应用，拖动悬浮摇杆；底部按钮切换步行、快走和跑步速度。
3. 松开摇杆会停止移动；显示“未连接”表示主应用代理未运行或虚拟定位未开启。
4. 点击 `−` 可折叠为“摇”按钮，点击“摇”恢复；点击 `×` 会完全关闭悬浮窗，重新在 AppsDump3 启动虚拟定位时自动显示。

安装后请先在 AppsDump3 内开启一次虚拟定位，再切换到目标 App。摇杆通过 Darwin 通知把位移交给 AppsDump3 的 `CLSimulationManager`，不需要 Wi-Fi 代理或断网。

AppsDump3 的页面右上角提供“摇杆”开关；关闭后会彻底隐藏悬浮窗并记住状态，点击悬浮窗的 `×` 也会同步关闭该开关。

兼容性：AppsDump3 4.0.6 的类和选择器已确认；若后续版本更改 `appendSimulatedLocation:`，摇杆会保持显示但不会移动位置。
