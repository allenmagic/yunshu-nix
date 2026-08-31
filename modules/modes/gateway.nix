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

    networking.defaultGateway = mkIf (g.upstreamGateway != null) {
      address = g.upstreamGateway;
      interface = "eth0";
    };

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
