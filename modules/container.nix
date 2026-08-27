{ config, lib, ... }:

with lib;

let
  cfg = config.yunshu.container;
in
{
  options.yunshu.container = {
    enable = mkEnableOption "YunShu proxy in a declarative NixOS container";

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
    ];

    containers.${cfg.name} = {
      autoStart = true;
      privateNetwork = true;
      enableTun = true;
      ephemeral = !cfg.persistState;
      config = cfg.guestModule;
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
