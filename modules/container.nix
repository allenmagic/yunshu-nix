{ config, lib, ... }:

with lib;

let
  cfg = config.yunshu.container;

  modeRegistry = {
    gateway = ./modes/gateway.nix;
    private_proxy = ./modes/private-proxy.nix;
    public_proxy = ./modes/public-proxy.nix;
    tproxy = ./modes/tproxy.nix;
  };

  identityConfig = {
    networking.hostName = cfg.hostname;
    environment.etc."machine-id".text = cfg.machineId;
  };

  macConfig = {
    systemd.network.networks."10-eth0" = {
      matchConfig.Name = "eth0";
      linkConfig.MACAddress = cfg.macAddress;
    };
  };
in
{
  imports = attrValues modeRegistry;

  options.yunshu.container = {
    enable = mkEnableOption "YunShu headless gateway or private proxy in a declarative NixOS container";

    mode = mkOption {
      type = types.enum (attrNames modeRegistry);
      default = "gateway";
      description = ''
        Deployment mode. Each mode lives in its own module and only enables
        the services that mode owns.
      '';
    };

    _modes = mkOption {
      type = types.attrsOf types.attrs;
      internal = true;
      default = {};
      description = "Guest configuration fragments contributed by mode modules.";
    };

    name = mkOption {
      type = types.str;
      default = "yunshu-router";
      description = "Name of the NixOS container.";
    };

    hostname = mkOption {
      type = types.str;
      default = "yunshu-router";
      description = "Fixed hostname inside the container (stable device identity).";
    };

    machineId = mkOption {
      type = types.str;
      default = "5212e91dae029bf58f9beffe3402c288";
      description = "Fixed systemd machine-id (32 lowercase hex chars, no dashes).";
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
      example = "192.168.10.3/24";
      description = "Container IP with prefix length when using bridge mode.";
    };

    lanAddress6 = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "fd00::50/64";
      description = "Optional IPv6 address with prefix length in bridge mode.";
    };

    macAddress = mkOption {
      type = types.nullOr types.str;
      default = "02:00:00:02:00:01";
      example = "02:00:00:02:00:01";
      description = "Fixed MAC address for the container's eth0 (bridge mode). Set null to auto-generate.";
    };

    forwardProxy = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Forward the proxy TCP port from the host to the container. Only used
        when networkMode = "nat"; normally enabled for proxy modes.
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
        services.yunshu headless, proxy and dns modules.
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
        assertion = cfg.mode != "gateway" || cfg.networkMode == "bridge";
        message = "yunshu.container.mode = \"gateway\" requires networkMode = \"bridge\".";
      }
    ];

    containers.${cfg.name} = {
      autoStart = true;
      privateNetwork = true;
      enableTun = true;
      ephemeral = !cfg.persistState;
      config = mkMerge [
        cfg.guestModule
        cfg._modes.${cfg.mode}
        identityConfig
        (mkIf (cfg.macAddress != null) macConfig)
      ];
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
