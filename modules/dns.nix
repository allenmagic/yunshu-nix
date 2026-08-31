{ config, lib, ... }:

with lib;

let
  cfg = config.services.yunshu.dns;
in
{
  options.services.yunshu.dns = {
    enable = mkEnableOption "DNS service inside the YunShu router VM";

    listen = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        Local address where YunShu's tunnel DNS listener is expected to bind
        (YunShu config field `dns-listen-addr`). The default matches the
        loopback DNS endpoint used by libtunnel.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 53;
      description = "UDP/TCP port for the DNS endpoint.";
    };

    transparentRedirect = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Transparently redirect LAN DNS traffic on port 53 to the container's
        local DNS endpoint. This is opt-in outside gateway mode and can be
        disabled explicitly even in gateway mode.
      '';
    };
  };

  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = mkIf (cfg.listen != "127.0.0.1" && cfg.listen != "::1") [ cfg.port ];
    networking.firewall.allowedUDPPorts = mkIf (cfg.listen != "127.0.0.1" && cfg.listen != "::1") [ cfg.port ];

    networking.nftables.enable = true;
    networking.nftables.tables.yunshu-dns = mkIf cfg.transparentRedirect {
      family = "inet";
      content = ''
        chain dns-dnat {
          type nat hook prerouting priority dstnat; policy accept;
          iifname "eth0" ip daddr != 127.0.0.1 udp dport 53 dnat to ${cfg.listen}:${toString cfg.port}
          iifname "eth0" ip daddr != 127.0.0.1 tcp dport 53 dnat to ${cfg.listen}:${toString cfg.port}
        }
      '';
    };
  };
}
