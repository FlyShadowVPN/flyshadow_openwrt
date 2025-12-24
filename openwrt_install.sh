#!/bin/sh

# FlyShadow OpenWrt 一键安装/卸载脚本
# 兼容新旧版本 OpenWrt (包括不支持 procd 的旧版本)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/etc/flyshadow"
BINARY_NAME="flyshadow_router"
SERVICE_NAME="flyshadow"
LUCI_CONTROLLER_DIR=""
LUCI_VIEW_DIR=""
LUCI_MENU_DIR=""
LUCI_VERSION=""
WEB_PORT="6780"

# 颜色输出 (使用 printf 保证兼容性)
log_info() {
    printf "\033[0;32m[INFO]\033[0m %s\n" "$1"
}

log_warn() {
    printf "\033[1;33m[WARN]\033[0m %s\n" "$1"
}

log_error() {
    printf "\033[0;31m[ERROR]\033[0m %s\n" "$1"
}

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

# 检查是否已安装
check_installed() {
    if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
        return 0
    fi
    return 1
}

# 检测系统信息
detect_system() {
    log_info "系统信息:"
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        printf "  OpenWrt 版本: %s\n" "${DISTRIB_RELEASE:-未知}"
        printf "  目标平台: %s\n" "${DISTRIB_TARGET:-未知}"
    fi
    printf "  内核版本: %s\n" "$(uname -r)"
    printf "  CPU 架构: %s\n" "$(uname -m)"
}

# 检测是否支持 procd
detect_procd() {
    if [ -f /lib/functions/procd.sh ] || grep -q "procd" /etc/init.d/* 2>/dev/null; then
        return 0
    fi
    return 1
}

# 检测 LuCI 版本和路径
detect_luci_version() {
    if [ -d "/www/luci-static" ]; then
        # 检查是否是新版 LuCI (使用 client-side rendering, OpenWrt 19.07+)
        if [ -d "/usr/share/luci/menu.d" ]; then
            LUCI_VERSION="new"
            LUCI_MENU_DIR="/usr/share/luci/menu.d"
            LUCI_CONTROLLER_DIR="/usr/share/rpcd/acl.d"
            log_info "检测到新版 LuCI (OpenWrt 19.07+)"
        else
            LUCI_VERSION="old"
            LUCI_CONTROLLER_DIR="/usr/lib/lua/luci/controller"
            LUCI_VIEW_DIR="/usr/lib/lua/luci/view"
            log_info "检测到旧版 LuCI"
        fi
    else
        log_warn "未检测到 LuCI，将跳过菜单安装"
        log_warn "您仍可通过 http://<路由器IP>:$WEB_PORT 访问"
        LUCI_VERSION="none"
    fi
}

# 创建 procd 启动脚本 (新版 OpenWrt)
create_procd_init_script() {
    cat > /etc/init.d/$SERVICE_NAME << 'INITEOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

PROG="/etc/flyshadow/flyshadow_router"
PIDFILE="/var/run/flyshadow.pid"

start_service() {
    procd_open_instance
    procd_set_param command $PROG
    procd_set_param respawn "${respawn_threshold:-3600}" "${respawn_timeout:-5}" "${respawn_retry:-5}"
    procd_set_param limits core="unlimited"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param pidfile $PIDFILE
    procd_close_instance
}

stop_service() {
    service_stop $PROG
}

reload_service() {
    stop
    start
}

service_triggers() {
    procd_add_reload_trigger "flyshadow"
}
INITEOF
    chmod +x /etc/init.d/$SERVICE_NAME
}

# 创建传统启动脚本 (旧版 OpenWrt，不支持 procd)
create_legacy_init_script() {
    cat > /etc/init.d/$SERVICE_NAME << 'INITEOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10

PROG="/etc/flyshadow/flyshadow_router"
PIDFILE="/var/run/flyshadow.pid"

start() {
    echo "Starting FlyShadow..."
    if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
        echo "FlyShadow is already running"
        return 0
    fi
    $PROG > /dev/null 2>&1 &
    echo $! > "$PIDFILE"
    echo "FlyShadow started"
}

stop() {
    echo "Stopping FlyShadow..."
    if [ -f "$PIDFILE" ]; then
        kill $(cat "$PIDFILE") 2>/dev/null
        rm -f "$PIDFILE"
    fi
    killall flyshadow_router 2>/dev/null
    echo "FlyShadow stopped"
}

restart() {
    stop
    sleep 1
    start
}

reload() {
    restart
}
INITEOF
    chmod +x /etc/init.d/$SERVICE_NAME
}

# 创建启动脚本 (自动选择)
create_init_script() {
    if detect_procd; then
        log_info "使用 procd 启动脚本"
        create_procd_init_script
    else
        log_info "使用传统启动脚本"
        create_legacy_init_script
    fi
    log_info "创建启动脚本 /etc/init.d/$SERVICE_NAME"
}

# 创建旧版 LuCI 控制器
create_old_luci_controller() {
    mkdir -p "$LUCI_CONTROLLER_DIR"
    cat > "$LUCI_CONTROLLER_DIR/flyshadow.lua" << 'LUAEOF'
module("luci.controller.flyshadow", package.seeall)

function index()
    entry({"admin", "services", "flyshadow"}, template("flyshadow/main"), _("FlyShadow"), 90).leaf = true
end
LUAEOF
    log_info "创建 LuCI 控制器"
}

# 创建旧版 LuCI 视图
create_old_luci_view() {
    mkdir -p "$LUCI_VIEW_DIR/flyshadow"
    cat > "$LUCI_VIEW_DIR/flyshadow/main.htm" << 'HTMEOF'
<%+header%>
<style>
    #flyshadow-container {
        margin: -20px;
        padding: 0;
    }
    #flyshadow-frame {
        width: 100%;
        height: calc(100vh - 120px);
        min-height: 600px;
        border: none;
        background: #fff;
    }
</style>
<div id="flyshadow-container">
    <iframe id="flyshadow-frame"></iframe>
</div>
<script type="text/javascript">
//<![CDATA[
    (function() {
        var host = window.location.hostname;
        var frame = document.getElementById('flyshadow-frame');
        frame.src = 'http://' + host + ':6780';
    })();
//]]>
</script>
<%+footer%>
HTMEOF
    log_info "创建 LuCI 视图"
}

# 创建新版 LuCI 菜单配置
create_new_luci_menu() {
    mkdir -p "$LUCI_MENU_DIR"
    cat > "$LUCI_MENU_DIR/luci-app-flyshadow.json" << 'JSONEOF'
{
    "admin/services/flyshadow": {
        "title": "FlyShadow",
        "order": 90,
        "action": {
            "type": "view",
            "path": "flyshadow/main"
        },
        "depends": {
            "acl": ["luci-app-flyshadow"],
            "uci": {}
        }
    }
}
JSONEOF
    log_info "创建 LuCI 菜单配置"
}

# 创建新版 LuCI ACL 配置
create_new_luci_acl() {
    mkdir -p "$LUCI_CONTROLLER_DIR"
    cat > "$LUCI_CONTROLLER_DIR/luci-app-flyshadow.json" << 'JSONEOF'
{
    "luci-app-flyshadow": {
        "description": "Grant access to FlyShadow",
        "read": {
            "ubus": {
                "luci": ["getFeatures"]
            },
            "file": {
                "/etc/flyshadow/*": ["read"]
            }
        },
        "write": {}
    }
}
JSONEOF
    log_info "创建 LuCI ACL 配置"
}

# 创建新版 LuCI 视图 (JS)
create_new_luci_view() {
    mkdir -p "/www/luci-static/resources/view/flyshadow"
    cat > "/www/luci-static/resources/view/flyshadow/main.js" << 'JSEOF'
'use strict';
'require view';
'require ui';

return view.extend({
    render: function() {
        var host = window.location.hostname;
        var protocol = window.location.protocol;
        var frameUrl = 'http://' + host + ':6780';

        var style = E('style', {}, [
            '#flyshadow-container { margin: -20px; padding: 0; }',
            '#flyshadow-frame { width: 100%; height: calc(100vh - 120px); min-height: 600px; border: none; background: #fff; }'
        ].join('\n'));

        var container = E('div', { 'id': 'flyshadow-container' }, [
            style,
            E('iframe', {
                'id': 'flyshadow-frame',
                'src': frameUrl,
                'allow': 'fullscreen'
            })
        ]);

        return container;
    },

    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
JSEOF
    log_info "创建 LuCI 视图"
}

# 配置防火墙
configure_firewall() {
    # 检查是否使用 fw4 (OpenWrt 22.03+) 或 fw3
    if command -v fw4 >/dev/null 2>&1; then
        # fw4 使用 nftables
        log_info "检测到 fw4 (nftables)"
        if ! nft list chain inet fw4 input 2>/dev/null | grep -q "tcp dport $WEB_PORT"; then
            # 添加防火墙规则到 /etc/nftables.d/ 或通过 uci
            if uci show firewall >/dev/null 2>&1; then
                uci -q delete firewall.flyshadow_web 2>/dev/null || true
                uci set firewall.flyshadow_web=rule
                uci set firewall.flyshadow_web.name='Allow-FlyShadow-Web'
                uci set firewall.flyshadow_web.src='lan'
                uci set firewall.flyshadow_web.dest_port="$WEB_PORT"
                uci set firewall.flyshadow_web.proto='tcp'
                uci set firewall.flyshadow_web.target='ACCEPT'
                uci commit firewall
                /etc/init.d/firewall reload 2>/dev/null || true
                log_info "添加防火墙规则 (端口 $WEB_PORT)"
            fi
        fi
    elif command -v fw3 >/dev/null 2>&1 || [ -f /etc/init.d/firewall ]; then
        # fw3 使用 iptables
        log_info "检测到 fw3 (iptables)"
        if ! uci -q get firewall.flyshadow_web >/dev/null 2>&1; then
            uci set firewall.flyshadow_web=rule
            uci set firewall.flyshadow_web.name='Allow-FlyShadow-Web'
            uci set firewall.flyshadow_web.src='lan'
            uci set firewall.flyshadow_web.dest_port="$WEB_PORT"
            uci set firewall.flyshadow_web.proto='tcp'
            uci set firewall.flyshadow_web.target='ACCEPT'
            uci commit firewall
            /etc/init.d/firewall reload 2>/dev/null || true
            log_info "添加防火墙规则 (端口 $WEB_PORT)"
        fi
    else
        log_warn "未检测到防火墙，跳过防火墙配置"
    fi
}

# 移除防火墙规则
remove_firewall() {
    if uci -q get firewall.flyshadow_web >/dev/null 2>&1; then
        uci delete firewall.flyshadow_web
        uci commit firewall
        /etc/init.d/firewall reload 2>/dev/null || true
        log_info "移除防火墙规则"
    fi
}

# 清除 LuCI 缓存
clear_luci_cache() {
    rm -rf /tmp/luci-indexcache 2>/dev/null || true
    rm -rf /tmp/luci-modulecache 2>/dev/null || true
    rm -rf /tmp/luci-* 2>/dev/null || true

    # 重启 rpcd 和 uhttpd 使配置生效
    if [ -f /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd restart 2>/dev/null || true
    fi
    if [ -f /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart 2>/dev/null || true
    fi
}

# 安装
install() {
    check_root
    detect_system

    log_info "开始安装 FlyShadow..."

    # 检查是否已安装
    if check_installed; then
        log_warn "FlyShadow 已安装，将进行升级..."
        # 停止现有服务
        /etc/init.d/$SERVICE_NAME stop 2>/dev/null || true
    fi

    # 检查二进制文件
    if [ ! -f "$SCRIPT_DIR/$BINARY_NAME" ]; then
        log_error "找不到 $BINARY_NAME"
        log_error "请确保二进制文件与脚本在同一目录: $SCRIPT_DIR"
        exit 1
    fi

    # 检查二进制文件是否可执行
    if ! file "$SCRIPT_DIR/$BINARY_NAME" 2>/dev/null | grep -q -E "(executable|ELF)"; then
        log_warn "无法验证二进制文件格式，继续安装..."
    fi

    # 检测 LuCI 版本
    detect_luci_version

    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    log_info "创建目录 $INSTALL_DIR"

    # 复制二进制文件
    cp "$SCRIPT_DIR/$BINARY_NAME" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    log_info "复制 $BINARY_NAME 到 $INSTALL_DIR"

    # 创建启动脚本
    create_init_script

    # 根据 LuCI 版本创建菜单
    if [ "$LUCI_VERSION" = "new" ]; then
        create_new_luci_menu
        create_new_luci_acl
        create_new_luci_view
    elif [ "$LUCI_VERSION" = "old" ]; then
        create_old_luci_controller
        create_old_luci_view
    fi

    # 配置防火墙
    configure_firewall

    # 启用并启动服务
    /etc/init.d/$SERVICE_NAME enable
    /etc/init.d/$SERVICE_NAME start
    log_info "启动 FlyShadow 服务"

    # 清除 LuCI 缓存
    if [ "$LUCI_VERSION" != "none" ]; then
        clear_luci_cache
    fi

    echo ""
    log_info "=========================================="
    log_info "安装完成！"
    log_info "=========================================="
    if [ "$LUCI_VERSION" != "none" ]; then
        log_info "请刷新浏览器，在 LuCI -> 服务 -> FlyShadow 中访问"
    fi
    log_info "或直接访问: http://$(uci -q get network.lan.ipaddr || echo '<路由器IP>'):$WEB_PORT"
    echo ""
}

# 卸载
uninstall() {
    check_root

    log_info "开始卸载 FlyShadow..."

    # 停止并禁用服务
    if [ -f "/etc/init.d/$SERVICE_NAME" ]; then
        /etc/init.d/$SERVICE_NAME stop 2>/dev/null || true
        /etc/init.d/$SERVICE_NAME disable 2>/dev/null || true
        rm -f /etc/init.d/$SERVICE_NAME
        log_info "移除启动脚本"
    fi

    # 确保进程已终止
    killall $BINARY_NAME 2>/dev/null || true

    # 删除安装目录
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        log_info "删除目录 $INSTALL_DIR"
    fi

    # 删除 PID 文件
    rm -f /var/run/flyshadow.pid 2>/dev/null || true

    # 删除 LuCI 相关文件 (新版)
    rm -f /usr/share/luci/menu.d/luci-app-flyshadow.json 2>/dev/null || true
    rm -f /usr/share/rpcd/acl.d/luci-app-flyshadow.json 2>/dev/null || true
    rm -rf /www/luci-static/resources/view/flyshadow 2>/dev/null || true
    rm -rf /usr/share/luci/view/flyshadow 2>/dev/null || true

    # 删除 LuCI 相关文件 (旧版)
    rm -f /usr/lib/lua/luci/controller/flyshadow.lua 2>/dev/null || true
    rm -rf /usr/lib/lua/luci/view/flyshadow 2>/dev/null || true

    # 移除防火墙规则
    remove_firewall

    # 清除 LuCI 缓存
    clear_luci_cache

    echo ""
    log_info "=========================================="
    log_info "卸载完成！"
    log_info "=========================================="
    echo ""
}

# 升级 (仅更新二进制文件)
upgrade() {
    check_root

    log_info "开始升级 FlyShadow..."

    if ! check_installed; then
        log_error "FlyShadow 未安装，请先执行安装"
        exit 1
    fi

    # 检查二进制文件
    if [ ! -f "$SCRIPT_DIR/$BINARY_NAME" ]; then
        log_error "找不到新的 $BINARY_NAME"
        exit 1
    fi

    # 停止服务
    /etc/init.d/$SERVICE_NAME stop 2>/dev/null || true

    # 备份旧文件
    if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
        cp "$INSTALL_DIR/$BINARY_NAME" "$INSTALL_DIR/${BINARY_NAME}.bak"
        log_info "备份旧版本到 ${BINARY_NAME}.bak"
    fi

    # 复制新文件
    cp "$SCRIPT_DIR/$BINARY_NAME" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    log_info "更新 $BINARY_NAME"

    # 启动服务
    /etc/init.d/$SERVICE_NAME start
    log_info "启动 FlyShadow 服务"

    echo ""
    log_info "升级完成！"
    echo ""
}

# 重启服务
restart() {
    check_root

    if [ -f "/etc/init.d/$SERVICE_NAME" ]; then
        /etc/init.d/$SERVICE_NAME restart
        log_info "FlyShadow 已重启"
    else
        log_error "FlyShadow 未安装"
        exit 1
    fi
}

# 显示状态
status() {
    echo ""
    echo "FlyShadow 状态"
    echo "=========================================="

    # 检查安装
    if check_installed; then
        printf "安装状态: \033[0;32m已安装\033[0m\n"
        printf "安装路径: %s\n" "$INSTALL_DIR/$BINARY_NAME"
    else
        printf "安装状态: \033[0;31m未安装\033[0m\n"
        return
    fi

    # 检查运行状态
    if pgrep -f "$INSTALL_DIR/$BINARY_NAME" > /dev/null 2>&1; then
        printf "运行状态: \033[0;32m运行中\033[0m\n"
        printf "进程 PID: %s\n" "$(pgrep -f "$INSTALL_DIR/$BINARY_NAME")"
    else
        printf "运行状态: \033[0;31m未运行\033[0m\n"
    fi

    # 检查开机启动
    if [ -f "/etc/init.d/$SERVICE_NAME" ]; then
        if ls /etc/rc.d/S*$SERVICE_NAME >/dev/null 2>&1; then
            printf "开机启动: \033[0;32m已启用\033[0m\n"
        else
            printf "开机启动: \033[0;33m未启用\033[0m\n"
        fi
    fi

    # 显示端口状态
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":$WEB_PORT"; then
            printf "Web 端口: \033[0;32m$WEB_PORT 已监听\033[0m\n"
        else
            printf "Web 端口: \033[0;33m$WEB_PORT 未监听\033[0m\n"
        fi
    fi

    # 显示访问地址
    LAN_IP=$(uci -q get network.lan.ipaddr 2>/dev/null || ip addr show br-lan 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$LAN_IP" ]; then
        printf "访问地址: http://%s:%s\n" "$LAN_IP" "$WEB_PORT"
    fi

    echo "=========================================="
    echo ""
}

# 显示日志
logs() {
    if command -v logread >/dev/null 2>&1; then
        logread | grep -i flyshadow | tail -50
    else
        log_warn "logread 不可用"
    fi
}

# 显示帮助
show_help() {
    echo ""
    echo "FlyShadow OpenWrt 安装脚本"
    echo "=========================================="
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  install   - 安装 FlyShadow (已安装则升级)"
    echo "  uninstall - 卸载 FlyShadow"
    echo "  upgrade   - 仅升级二进制文件"
    echo "  restart   - 重启服务"
    echo "  status    - 查看运行状态"
    echo "  logs      - 查看日志"
    echo "  help      - 显示此帮助"
    echo ""
    echo "示例:"
    echo "  $0 install    # 安装或升级"
    echo "  $0 uninstall  # 完全卸载"
    echo "  $0 status     # 查看状态"
    echo ""
}

# 交互式菜单
interactive_menu() {
    echo ""
    echo "FlyShadow OpenWrt 安装脚本"
    echo "=========================================="
    echo ""
    echo "请选择操作:"
    echo "  1) 安装/升级"
    echo "  2) 卸载"
    echo "  3) 重启服务"
    echo "  4) 查看状态"
    echo "  5) 查看日志"
    echo "  6) 退出"
    echo ""
    printf "请输入选项 [1-6]: "
    read -r choice
    case "$choice" in
        1) install ;;
        2) uninstall ;;
        3) restart ;;
        4) status ;;
        5) logs ;;
        6) exit 0 ;;
        *) log_error "无效选项" ;;
    esac
}

# 主逻辑
case "${1:-}" in
    install)
        install
        ;;
    uninstall|remove)
        uninstall
        ;;
    upgrade|update)
        upgrade
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs|log)
        logs
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        interactive_menu
        ;;
    *)
        log_error "未知命令: $1"
        show_help
        exit 1
        ;;
esac

exit 0
