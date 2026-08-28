{ config, lib, ... }:

with lib;

let
  cfg = config.yunshu.container;

  gatewayConfig = {
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = true;
      "net.ipv6.conf.all.forwarding" = true;
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
    };

    networking.nftables.enable = true;

    networking.firewall = {
      filterForward = true;
      extraForwardRules = ''
        iifname "eth0" accept
        iifname "tun0" accept
      '';
    };

    # Gateway mode uses YunShu's own TUN routing, not the separate 7890 proxy.
    services.yunshu.proxy.enable = mkForce false;

    # 直连流量出口：上游路由器（Alpine VM 的 LAN IP）
    networking.defaultGateway = mkIf (cfg.upstreamGateway != null) {
      address = cfg.upstreamGateway;
      interface = "eth0";
    };

    # 浮动网关（VRRP）——MASTER 节点（与 Alpine VM 的 BACKUP 配对）
    # 参数与 alpine-router-image 的 base/keepalived/keepalived.conf 对齐
    services.keepalived = {
      enable = true;
      vrrpInstances.LAN = {
        state = "MASTER";
        interface = "eth0";
        virtualRouterId = cfg.vrrpId;
        priority = 150;
        virtualIps = [ { addr = "${cfg.floatIp}/24"; } ];
        # nixpkgs 26.05 的 keepalived 模块无 advert/auth 字段，走 extraConfig
        extraConfig = ''
          advert_int 1
          authentication {
            auth_type PASS
            auth_pass ${cfg.authPass}
          }
        '';
      };
    };
  };
in
{
  options.yunshu.container = {
    enable = mkEnableOption "YunShu headless gateway/proxy in a declarative NixOS container";

    gatewayMode = mkEnableOption "transparent LAN gateway mode";

    name = mkOption {
      type = types.str;
      default = "yunshu-router";
      description = "Name of the NixOS container.";
    };

    hostAddress = mkOption {
      type = types.str;
      default = "10.100.0.1";
      description = "IPv4 address of the host side of the container veth.";
    };

    localAddress = mkOption {
      type = types.str;
      default = "10.100.0.2";
      description = "IPv4 address assigned inside the container.";
    };

    networkMode = mkOption {
      type = types.enum [ "nat" "bridge" ];
      default = "bridge";
      description = ''
        How the container is attached to the network.

        - nat: private veth + host address; proxy port is forwarded to the host.
        - bridge: attach the container veth to an existing host bridge and give
          the container its own LAN IP.
      '';
    };

    bridge = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "br0";
      description = "Existing host bridge used when networkMode = \"bridge\".";
    };

    lanAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "192.168.1.50/24";
      description = "Container IP with prefix length when using bridge mode.";
    };

    lanAddress6 = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "fd00::50/64";
      description = "Optional IPv6 address with prefix length in bridge mode.";
    };

    forwardProxy = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Forward the proxy TCP port from the host to the container. Only used
        when networkMode = "nat".
      '';
    };

    proxyPort = mkOption {
      type = types.int;
      default = 7890;
      description = "Proxy port to expose from the host.";
    };

    persistState = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Persist the container root filesystem, including /var/lib/yunshu login
        tokens. Disable only for stateless/throwaway instances.
      '';
    };

    upstreamGateway = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "192.168.10.1";
      description = ''
        Direct-traffic upstream gateway (usually the router VM's LAN IP).
        Set in gateway mode so the container routes non-proxied traffic
        through the upstream router.
      '';
    };

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

    guestModule = mkOption {
      type = types.deferredModule;
      description = ''
        NixOS module evaluated inside the container. Usually this imports
        services.yunshu headless and proxy modules.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.networkMode != "bridge" || (cfg.bridge != null && cfg.lanAddress != null);
        message = "yunshu.container.bridge and yunshu.container.lanAddress are required in bridge mode.";
      }
      {
        assertion = !cfg.gatewayMode || cfg.networkMode == "bridge";
        message = "yunshu.container.gatewayMode requires networkMode = \"bridge\".";
      }
    ];

    containers.${cfg.name} = {
      autoStart = true;
      privateNetwork = true;
      enableTun = true;
      ephemeral = !cfg.persistState;
      config = mkMerge [ cfg.guestModule (mkIf cfg.gatewayMode gatewayConfig) ];
    } // (if cfg.networkMode == "bridge" then {
      hostBridge = cfg.bridge;
      localAddress = cfg.lanAddress;
      localAddress6 = cfg.lanAddress6;
    } else {
      hostAddress = cfg.hostAddress;
      localAddress = cfg.localAddress;
      forwardPorts = optionals cfg.forwardProxy [{
        protocol = "tcp";
        hostPort = cfg.proxyPort;
        containerPort = cfg.proxyPort;
      }];
    });
  };
}
