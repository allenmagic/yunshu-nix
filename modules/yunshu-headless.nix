{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.yunshu;

  payloadSrc = builtins.path {
    name = "yunshu-headless-payload";
    path = cfg.package;
    filter = path: type:
      type == "directory"
      || builtins.elem
        (removePrefix (toString cfg.package + "/") (toString path))
        [
          "opt/apps/yunshu/files/bin/yunshu"
          "opt/apps/yunshu/files/bin/yunshu-daemon"
          "opt/apps/yunshu/files/bin/yunshu-updater"
          "opt/apps/yunshu/files/bin/libtunnel.so"
          "opt/apps/yunshu/files/bin/exec/executor"
          "opt/apps/yunshu/files/system/yunshu-daemon.service"
          "opt/apps/yunshu/files/system/yunshu-updater.service"
          "opt/apps/yunshu/files/config/version.ini"
        ];
  };

  runtimePackage = pkgs.stdenvNoCC.mkDerivation {
    name = "yunshu-headless-2.3.10.30";
    src = payloadSrc;
    dontUnpack = true;

    installPhase = ''
      mkdir -p "$out/opt/apps/yunshu/files"
      cp -a "${payloadSrc}/opt/apps/yunshu/files/bin" "$out/opt/apps/yunshu/files/bin"
      cp -a "${payloadSrc}/opt/apps/yunshu/files/system" "$out/opt/apps/yunshu/files/system"

      mkdir -p "$out/opt/apps/yunshu/files/config"
      cp "${payloadSrc}/opt/apps/yunshu/files/config/version.ini" \
        "$out/opt/apps/yunshu/files/config/version.ini"

      chmod 0755 \
        "$out/opt/apps/yunshu/files" \
        "$out/opt/apps/yunshu/files/bin" \
        "$out/opt/apps/yunshu/files/bin/yunshu" \
        "$out/opt/apps/yunshu/files/bin/yunshu-daemon" \
        "$out/opt/apps/yunshu/files/bin/yunshu-updater" \
        "$out/opt/apps/yunshu/files/bin/exec/executor"
      chmod 0644 "$out/opt/apps/yunshu/files/bin/libtunnel.so"
    '';
  };

  binDir = "${runtimePackage}/opt/apps/yunshu/files/bin";
  systemDir = "${runtimePackage}/opt/apps/yunshu/files/system";
  stateDir = "/var/lib/yunshu";

  yunshuCli = pkgs.writeShellScriptBin "yunshu" ''
    exec ${binDir}/yunshu "$@"
  '';

  initScript = ''
    mkdir -p \
      /opt/apps/yunshu/files \
      ${stateDir}/{config,socket,tmp,bak,logs}

    ln -sfn ${binDir} /opt/apps/yunshu/files/bin
    ln -sfn ${systemDir} /opt/apps/yunshu/files/system
    ln -sfn ${stateDir}/config /opt/apps/yunshu/files/config
    ln -sfn ${stateDir}/socket /opt/apps/yunshu/files/socket
    ln -sfn ${stateDir}/tmp /opt/apps/yunshu/files/tmp
    ln -sfn ${stateDir}/bak /opt/apps/yunshu/files/bak
    ln -sfn ${stateDir}/logs /opt/apps/yunshu/files/logs

    chmod 0755 \
      /opt/apps/yunshu/files \
      ${stateDir}/socket \
      ${stateDir}/tmp \
      ${stateDir}/bak \
      ${stateDir}/logs

    if [ ! -f ${stateDir}/config/version.ini ]; then
      cp "${runtimePackage}/opt/apps/yunshu/files/config/version.ini" \
        ${stateDir}/config/version.ini
    fi

    if [ ! -f ${stateDir}/config/private_ctl.conf ]; then
      printf '%s\n' "${cfg.spAddr}" > ${stateDir}/config/private_ctl.conf
    fi

    if [ ! -f ${stateDir}/config/app_config.json ]; then
      cat > ${stateDir}/config/app_config.json <<EOF
{
  "corpcode": "${cfg.corpCode}",
  "sp_addr": "${cfg.spAddr}"
}
EOF
    fi
  '';

  loginScript = pkgs.writeShellScript "yunshu-login" ''
    set -euo pipefail
    export BROWSER=""
    # 优先选飞书 SSO；如果只有短信源，则退化为交互输入。
    if printf '1\n' | ${binDir}/yunshu -c "${cfg.corpCode}" -l; then
      mkdir -p "${stateDir}/config"
      touch "${stateDir}/config/.logged-in"
    fi
  '';
in
{
  options.services.yunshu = {
    enable = mkEnableOption "YunShu headless daemon and updater";

    package = mkOption {
      type = types.path;
      default = ../dist/yunshu-headless;
      description = ''
        Directory containing the stripped headless payload, i.e.
        dist/yunshu-headless from the original unpacked .deb.
      '';
    };

    corpCode = mkOption {
      type = types.str;
      default = "cpe";
      description = "YunShu corporate/enterprise code.";
    };

    spAddr = mkOption {
      type = types.str;
      default = "https://sp.eagleyun.cn/";
      description = "YunShu private SP endpoint.";
    };

    loginOnStart = mkOption {
      type = types.bool;
      default = true;
      description = "Attempt Feishu/SMS login at boot; URL is visible in the journal.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ yunshuCli ];

    systemd.services.yunshu-init = {
      description = "Prepare YunShu headless runtime state";
      wantedBy = [ "multi-user.target" ];
      before = [ "yunshu-daemon.service" "yunshu-updater.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = initScript;
    };

    systemd.services.yunshu-daemon = {
      description = "YunShu headless daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "yunshu-init.service" ];
      wants = [ "network-online.target" ];
      requires = [ "yunshu-init.service" ];
      serviceConfig = {
        ExecStart = "${binDir}/yunshu-daemon -d";
        Restart = "on-failure";
        RestartSec = 5;
        WorkingDirectory = stateDir;
        LimitNOFILE = 65536;
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_SYS_ADMIN" ];
      };
    };

    systemd.services.yunshu-updater = {
      description = "YunShu headless updater";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "yunshu-daemon.service" "yunshu-init.service" ];
      wants = [ "network-online.target" ];
      requires = [ "yunshu-init.service" ];
      serviceConfig = {
        ExecStart = "${binDir}/yunshu-updater -d";
        Restart = "on-failure";
        RestartSec = 5;
        WorkingDirectory = stateDir;
        LimitNOFILE = 65536;
      };
    };

    systemd.services.yunshu-login = mkIf cfg.loginOnStart {
      description = "YunShu headless login";
      wantedBy = [ "multi-user.target" ];
      after = [ "yunshu-daemon.service" "yunshu-updater.service" ];
      unitConfig.ConditionPathExists = "!${stateDir}/config/.logged-in";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${loginScript}/bin/yunshu-login";
        Restart = "on-failure";
        RestartSec = 10;
        WorkingDirectory = stateDir;
      };
    };
  };
}
