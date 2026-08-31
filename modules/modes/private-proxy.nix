{ config, lib, ... }:

with lib;

let
  cfg = config.yunshu.container;
in
{
  config.yunshu.container._modes.private_proxy = mkIf (cfg.mode == "private_proxy") {
    services.yunshu.proxy.enable = mkDefault true;
    services.yunshu.dns.enable = mkDefault false;
    services.keepalived.enable = mkForce false;
  };
}
