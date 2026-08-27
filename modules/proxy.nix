{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.yunshu;
  proxy = cfg.proxy;
in
{
  options.services.yunshu.proxy = {
    enable = mkEnableOption "proxy service inside the YunShu router VM";

    backend = mkOption {
      type = types.enum [ "3proxy" "sing-box" ];
      default = "3proxy";
      description = ''
        Proxy implementation. Defaults to 3proxy because the proxy is exposed
        on a trusted LAN and does not need encrypted transport.
      '';
    };

    listen = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address the mixed HTTP/SOCKS inbound listens on.";
    };

    listenPort = mkOption {
      type = types.int;
      default = 7890;
      description = "TCP port for the mixed HTTP/SOCKS inbound.";
    };

    extraSettings = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        Extra sing-box settings merged on top of the default mixed proxy
        configuration. Only used when backend = "sing-box".
      '';
    };

    threeProxyServices = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = ''
        Extra 3proxy service entries merged after the default mixed proxy.
        Only used when backend = "3proxy".
      '';
    };
  };

  config = mkIf (cfg.enable && proxy.enable) (mkMerge [
    {
      networking.firewall.allowedTCPPorts = [ proxy.listenPort ];
    }

    (mkIf (proxy.backend == "3proxy") {
      services._3proxy = {
        enable = true;
        # 内网代理需要访问企业内网/私网目标，不能默认拒绝 private ranges。
        denyPrivate = false;
        services = [{
          type = "auto";
          bindAddress = proxy.listen;
          bindPort = proxy.listenPort;
          auth = [ "none" ];
        }] ++ proxy.threeProxyServices;
      };

      systemd.services."3proxy" = {
        after = [ "yunshu-daemon.service" "yunshu-updater.service" ];
        wants = [ "yunshu-daemon.service" "yunshu-updater.service" ];
      };
    })

    (mkIf (proxy.backend == "sing-box") {
      services.sing-box = {
        enable = true;
        settings = recursiveUpdate {
          log = {
            level = "info";
            timestamp = true;
          };
          inbounds = [{
            type = "mixed";
            tag = "mixed-in";
            listen = proxy.listen;
            listen_port = proxy.listenPort;
          }];
          outbounds = [{
            type = "direct";
            tag = "direct";
          }];
        } proxy.extraSettings;
      };

      systemd.services.sing-box = {
        after = [ "yunshu-daemon.service" "yunshu-updater.service" ];
        wants = [ "yunshu-daemon.service" "yunshu-updater.service" ];
      };
    })
  ]);
}
