# yunshu-nix

把 `YunShu_2.3.10.30_cpe.deb` 剥离 GUI 后的 headless 后台服务，跑在一个
NixOS declarative container 里。默认以透明网关模式接入局域网，复用 YunShu
自带的 TUN 分流；也可以关闭 `gatewayMode`，退回 3proxy/sing-box 代理模式。

详细部署、登录、排障和备份说明见 [docs/使用手册.md](./docs/使用手册.md)。

## 默认配置

- 运行时 payload 来自 `dist/yunshu-headless/`
- 默认模式：`gatewayMode = true`，容器作为局域网默认网关，直接复用 YunShu TUN 分流
- 可选代理模式：关闭 `gatewayMode` 后启用 `3proxy`/`sing-box`，监听 `0.0.0.0:7890`
- 默认企业码：`cpe`，SP 地址：`https://sp.eagleyun.cn/`
- 网络模式：`bridge`，容器拥有独立局域网 IP
- 容器 root 文件系统默认持久化，登录 token 落在容器内 `/var/lib/yunshu`

## 目录结构

```text
flake.nix
modules/
  yunshu-headless.nix    # yunshu 运行时 + systemd 服务 + 登录服务
  proxy.nix              # 3proxy/sing-box 代理服务与防火墙
  container.nix          # NixOS declarative container 网络和持久化配置
examples/
  container-flake.nix    # 在现有 NixOS host 上导入该容器的完整示例
docs/
  使用手册.md
```

## 在现有 NixOS host 上部署

完整示例见 [`examples/container-flake.nix`](./examples/container-flake.nix)。
最小配置：

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    yunshu-router = {
      url = "path:/home/allenmagic/Projects/yunshu-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, yunshu-router, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        yunshu-router.nixosModules.container

        {
          networking.hostName = "router-host";

          # 宿主机需要先有 br0 bridge。
          networking.bridges.br0.interfaces = [ "eth0" ];
          networking.interfaces.br0.useDHCP = true;

          yunshu.container = {
            enable = true;
            gatewayMode = true;
            networkMode = "bridge";
            bridge = "br0";
            lanAddress = "192.168.1.50/24";
          };
        }
      ];
    };
  };
}
```

重建 host：

```sh
sudo nixos-rebuild switch --flake .#host
```

局域网设备把默认网关指向容器 IP：

```text
192.168.1.50
```

DNS 也建议指向容器，或后续在容器内做 53 端口透明重定向。

## 容器网络

`modules/container.nix` 提供 `bridge` 和 `nat` 两种接入模式，默认是 `bridge`。
透明网关模式要求使用 `bridge`。

### 透明网关

```nix
yunshu.container = {
  enable = true;
  gatewayMode = true;
  networkMode = "bridge";
  bridge = "br0";
  lanAddress = "192.168.1.50/24";
};
```

网关模式会在容器内开启 IP 转发、关闭 ICMP redirect、放行 `eth0 <-> tun0`
转发，并关闭独立的 7890 代理。局域网设备只需把默认网关指向容器 LAN IP。

### bridge

容器 eth0 直接接入宿主机已有 bridge，并获得独立局域网 IP：

```nix
yunshu.container = {
  enable = true;
  networkMode = "bridge";
  bridge = "br0";
  lanAddress = "192.168.1.50/24";
};
```

宿主机需要提前配置 bridge。虽然宿主机 IP/NAT 故障时容器仍可能工作，但物理网卡
或 bridge 本身失效时容器也会断。

### nat

如果暂时不能建 bridge，可以用私有 veth + 端口转发：

```nix
yunshu.container = {
  enable = true;
  gatewayMode = false;
  networkMode = "nat";
  hostAddress = "10.100.0.1";
  localAddress = "10.100.0.2";
  forwardProxy = true;
  proxyPort = 7890;
};
```

## 登录与状态持久化

`yunshu-headless.nix` 会启动：

- `yunshu-init.service`
- `yunshu-daemon.service`
- `yunshu-updater.service`
- 默认启用的 `yunshu-login.service`

登录状态保存在容器内的 `/var/lib/yunshu`。容器模块默认：

- `persistState = true`
- `ephemeral = false`

因此容器重启或宿主机重启后，登录 token、`config.db` 和缓存会保留，不会每次
都要求重新登录。

`yunshu-login.service` 登录成功后会在
`/var/lib/yunshu/config/.logged-in` 写标记；服务再次启动时会检查该标记，已经
登录过就不会重复跑交互式飞书流程。

首次登录或 token 过期时，查看登录 URL/二维码：

```sh
sudo journalctl -M yunshu-router -u yunshu-login -f
```

如果希望强制重新登录：

```sh
sudo nixos-container run yunshu-router -- \
  rm -f /var/lib/yunshu/config/.logged-in
sudo nixos-container run yunshu-router -- \
  systemctl restart yunshu-login
```

## 代理

默认使用 `3proxy`，因为它是一个很小的 C 实现，适合纯内网、无加密的转发场景。
代理监听 `0.0.0.0:7890`，`auto` 模式会在同一端口上自动识别 HTTP 和 SOCKS 协议。

由于这是内网 VPN 代理，默认关闭了 3proxy 的 `denyPrivate`，允许访问企业内网和
私网目标。当前也默认 `auth = [ "none" ]`；如果需要额外入口或自定义服务，可以在
`services.yunshu.proxy.threeProxyServices` 中追加 3proxy service 定义。

## 覆盖服务参数

```nix
yunshu.container.guestModule = {
  services.yunshu = {
    corpCode = "cpe";
    spAddr = "https://sp.eagleyun.cn/";
    loginOnStart = true;
  };

  services.yunshu.proxy = {
    enable = true;
    backend = "3proxy";
    listen = "0.0.0.0";
    listenPort = 7890;
  };
};
```

## 注意

- `yunshu` 安装路径被二进制硬编码为 `/opt/apps/yunshu`，模块通过
  `/opt/apps/yunshu/files` 下的符号链接映射到不可变 store 和可写
  `/var/lib/yunshu` 状态目录。
- 容器需要 `/dev/net/tun` 和 `CAP_NET_ADMIN`，`modules/container.nix` 已经通过
  `enableTun = true` 提供；宿主机内核仍需支持 `tun` 模块。
