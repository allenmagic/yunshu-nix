{ config, lib, ... }:

with lib;

let
  cfg = config.yunshu.container;
  g = config.yunshu.container.gateway;
in
{
  options.yunshu.container.gateway = {
    floatIp = mkOption {
      type = types.str;
      default = "192.168.10.254";
      description = ''
        VRRP floating IP held by MASTER (this container) and taken over by
        the BACKUP (router VM) when the container is unavailable. Must match
        alpine-router-image's keepalived.conf and LAN_GATEWAY.
      '';
    };

    vrrpId = mkOption {
      type = types.int;
      default = 10;
      description = "VRRP virtual_router_id, shared with the BACKUP node.";
    };

    authPass = mkOption {
      type = types.str;
      default = "alpine-float";
      description = "VRRP authentication pass, shared with the BACKUP node.";
    };

  };

  config.yunshu.container._modes.gateway = mkIf (cfg.mode == "gateway") {
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = true;
      "net.ipv6.conf.all.forwarding" = true;
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
    };

    networking.nftables.enable = true;

    # SNAT/masquerade：下游设备直连流量经 eth0 出去时，把源地址改成容器自身
    #（192.168.10.3），否则回包从上游直接绕回下游设备、绕开本容器 → 非对称
    # 路由丢包。隧道流量（走 tun0）由 yunshu 隧道自身处理，不需 masquerade。
    networking.nftables.tables.yunshu-snat = {
      family = "ip";
      content = ''
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          oifname "eth0" masquerade
        }
      '';
    };

    networking.firewall = {
      filterForward = true;
      extraForwardRules = ''
        iifname "eth0" accept
        iifname "tun0" accept
      '';
    };

    # Gateway mode uses YunShu's own TUN routing, not the separate 7890 proxy.
    services.yunshu.proxy.enable = mkForce false;

    # Transparent gateway also owns DNS by default, but both can be disabled
    # explicitly by the deployer.
    services.yunshu.dns.enable = mkDefault true;
    services.yunshu.dns.transparentRedirect = mkDefault true;

    # 默认路由已由 container.nix 的 identityConfig 统一设置（所有 bridge 模式
    # 都经上游网关出网），此处不再重复。

    # 容器自身 DNS 统一由 container.nix 的 upstreamGateway 处理（写死
    # /etc/resolv.conf 指上游网关），此处不再重复。

    services.keepalived = {
      enable = true;
      vrrpInstances.LAN = {
        state = "MASTER";
        interface = "eth0";
        virtualRouterId = g.vrrpId;
        priority = 150;
        virtualIps = [ { addr = "${g.floatIp}/24"; } ];
        extraConfig = ''
          advert_int 1
          authentication {
            auth_type PASS
            auth_pass ${g.authPass}
          }
        '';
      };
    };
  };
}
