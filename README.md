# flyshadow_openwrt
FlyShadowVPN 路由端安装脚本

FlyShadow OpenWrt 安装脚本使用说明

  前置条件

  1. 将 openwrt_install.sh 和 flyshadow_router 二进制文件放在同一目录
  2. 使用 root 用户运行

  命令用法

  # 赋予执行权限
  chmod +x openwrt_install.sh

  # 安装（已安装则自动升级）
  ./openwrt_install.sh install

  # 卸载
  ./openwrt_install.sh uninstall

  #仅升级二进制文件
  ./openwrt_install.sh upgrade

  # 重启服务
  ./openwrt_install.sh restart

  # 查看运行状态
  ./openwrt_install.sh status

  # 查看日志
  ./openwrt_install.sh logs

  # 显示帮助
  ./openwrt_install.sh help

  # 交互式菜单（不带参数）
  ./openwrt_install.sh

  访问方式

  安装完成后：
  - LuCI 菜单: 服务 → FlyShadow
  - 直接访问: http://<路由器IP>:6780

  兼容性

  - 支持 OpenWrt 新旧版本（包括不支持 procd 的旧版本）
  - 自动检测 LuCI 版本并适配
  - 自动配置防火墙规则
