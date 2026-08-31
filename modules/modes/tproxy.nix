{ config, lib, ... }:

with lib;

let
  cfg = config.yunshu.container;
in
{
  config = mkIf (cfg.mode == "tproxy") {
    yunshu.container._modes.tproxy = {
      services.yunshu.proxy.enable = mkForce false;
      services.yunshu.dns.enable = mkDefault false;
    };

    assertions = [{
      assertion = false;
      message = "yunshu.container.mode = \"tproxy\" is reserved but not implemented yet.";
    }];
  };
}
