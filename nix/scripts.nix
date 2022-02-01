{ evalService
, project
, customConfigs
}:
with project.pkgs;
let
  mkScript = envConfig:
    let
      service = evalService {
        inherit pkgs customConfigs;
        serviceName = "cardano-ogmios";
        modules = [
          ./nixos/cardano-ogmios-service.nix
          {
            services.cardano-ogmios = {
              nodeConfig = lib.mkDefault (builtins.toFile "${envConfig.name}-config.json" (builtins.toJSON envConfig.nodeConfig));
              package = lib.mkDefault project.hsPkgs.ogmios.components.exes.ogmios;
            };
          }
        ];
      };
    in
    lib.recurseIntoAttrs {
      ogmios = pkgs.writeScriptBin "ogmios-${envConfig.name}" ''
        #!${pkgs.runtimeShell}
        set -euo pipefail
        exec ${service.command} $@
      '';
    };
in
cardanoLib.forEnvironments mkScript
