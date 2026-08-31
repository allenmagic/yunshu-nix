{ config, lib, ... }:

with lib;

let
  cfg = config.yunshu.container;
  p = config.yunshu.container.publicProxy;
in
{
  options.yunshu.container.publicProxy = {
    auth = mkOption {
      type = types.listOf (types.enum [ "none" "iponly" "strong" ]);
      default = [ "iponly" ];
      description = "Authentication method for the public 3proxy inbound.";
    };

    allowFrom = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "203.0.113.0/24" ];
      description = "Source networks allowed to reach the public proxy.";
    };

    denyPrivate = mkOption {
      type = types.bool;
      default = true;
      description = "Deny access to private IP ranges from the public proxy.";
    };

    usersFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Optional 3proxy users file when auth includes strong.";
    };
  };

  config = mkIf (cfg.mode == "public_proxy") {
    yunshu.container._modes.public_proxy = {
      services.yunshu.proxy.enable = mkDefault true;
      services.yunshu.proxy.auth = mkDefault p.auth;
      services.yunshu.proxy.denyPrivate = mkDefault p.denyPrivate;
      services.yunshu.proxy.usersFile = mkDefault p.usersFile;
      services.yunshu.proxy.acl = mkDefault (optional (p.allowFrom != []) {
        rule = "allow";
        sources = p.allowFrom;
      });
      services.yunshu.dns.enable = mkDefault false;
      services.keepalived.enable = mkForce false;
    };

    assertions = [{
      assertion = p.allowFrom != [];
      message = "yunshu.container.mode = \"public_proxy\" requires publicProxy.allowFrom to be non-empty.";
    }];
  };
}
