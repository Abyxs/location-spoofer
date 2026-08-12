# Paopao Joystick (RootHide)

## 构建安装

需要 macOS、Theos、RootHide Bootstrap 工具链和可访问设备的 SSH。

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

仅监听 `127.0.0.1:8888`，每次更新最大位移 5 米。重启主应用后会恢复应用内最后保存的位置。
