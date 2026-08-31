{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.yunshu;
  proxy = cfg.proxy;
in
{
  options.services.yunshu.proxy = {
    enable = mkEnableOption "proxy service inside the YunShu router VM";

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

    denyPrivate = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether 3proxy should refuse private IP targets. False is the safe
        default for the trusted-LAN private_proxy mode.
      '';
    };

    auth = mkOption {
      type = types.listOf (types.enum [ "none" "iponly" "strong" ]);
      default = [ "none" ];
      description = "3proxy authentication method for the default mixed inbound.";
    };

    usersFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Optional 3proxy users file for strong authentication.";
    };

    acl = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "3proxy ACL entries for the default mixed inbound.";
    };

    threeProxyServices = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "Extra 3proxy service entries merged after the default mixed proxy.";
    };
  };

  config = mkIf (cfg.enable && proxy.enable) {
    networking.firewall.allowedTCPPorts = [ proxy.listenPort ];

    services._3proxy = {
      enable = true;
      # 内网代理默认允许访问企业内网/私网目标；public_proxy 会覆盖为 true。
      denyPrivate = proxy.denyPrivate;
      usersFile = proxy.usersFile;
      services = [{
        type = "auto";
        bindAddress = proxy.listen;
        bindPort = proxy.listenPort;
        auth = proxy.auth;
        acl = proxy.acl;
      }] ++ proxy.threeProxyServices;
    };

    systemd.services."3proxy" = {
      after = [ "yunshu-daemon.service" "yunshu-updater.service" ];
      wants = [ "yunshu-daemon.service" "yunshu-updater.service" ];
    };
  };
}
