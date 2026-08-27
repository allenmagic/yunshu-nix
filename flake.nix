{
  description = "YunShu headless proxy in a NixOS declarative container";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosModules = {
      yunshu-headless = ./modules/yunshu-headless.nix;
      proxy = ./modules/proxy.nix;

      # 在现有 NixOS host 上直接 import 这个模块，启用并声明
      # yunshu-router container。guest 内复用 headless 和 proxy 模块。
      container = {
        imports = [ ./modules/container.nix ];

        yunshu.container.enable = true;
        yunshu.container.guestModule = {
          imports = [
            self.nixosModules.yunshu-headless
            self.nixosModules.proxy
          ];

          system.stateVersion = "26.11";
          services.yunshu.enable = true;
          services.yunshu.proxy.enable = true;
        };
      };
    };
  };
}
