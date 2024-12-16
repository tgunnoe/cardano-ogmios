{
  description = "cardano-ogmios";

  inputs = {
    ogmios = {
      url = "github:CardanoSolutions/ogmios/v6.7.0";
      flake = false;
    };
    haskellNix = {
      url = "github:input-output-hk/haskell.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    CHaP = {
      url = "github:intersectMBO/cardano-haskell-packages/repo";
      flake = false;
    };
    iohkNix = {
      url = "github:input-output-hk/iohk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    config.url = "github:input-output-hk/empty-flake";
  };

  outputs = { self, ogmios, iohkNix, haskellNix, CHaP, nixpkgs, flake-utils, config, ... }:
    let
      inherit (nixpkgs) lib;
      inherit (flake-utils.lib) eachSystem flattenTree;
      inherit (iohkNix.lib) evalService;

      supportedSystems = config.supportedSystems or (import ./nix/supported-systems.nix);

      # Ogmios repo still declares the cardano-haskell-packages repository using the legacy iohk url
      inputMap = { "https://input-output-hk.github.io/cardano-haskell-packages" = CHaP; };

      overlay = final: prev: {
        ogmiosHaskellProject = self.legacyPackages.${final.system};
        inherit (final.cardanoOgmiosHaskellProject.hsPkgs.ogmios.components.exes) ogmios;
      };

      nixosModule = { pkgs, lib, ... }: {
        imports = [ ./nix/nixos/cardano-ogmios-service.nix ];
        services.cardano-ogmios.package = lib.mkDefault self.defaultPackage.${pkgs.system};
      };

    in
    eachSystem supportedSystems
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            inherit (haskellNix) config;
            overlays = [
              iohkNix.overlays.crypto
              haskellNix.overlay
              iohkNix.overlays.haskell-nix-extra
              iohkNix.overlays.haskell-nix-crypto
              iohkNix.overlays.cardano-lib
              iohkNix.overlays.utils
              overlay
            ];
          };

          project = (import ./nix/haskell.nix pkgs.haskell-nix ogmios inputMap).appendModule (config.haskellNix or { });

          scripts = flattenTree (import ./nix/scripts.nix {
            inherit project evalService;
            customConfigs = [ config ];
          });

          packages = {
            inherit (project.hsPkgs.ogmios.components.exes) ogmios;
          } // scripts;

          apps = lib.mapAttrs (n: p: { type = "app"; program = p.exePath or "${p}/bin/${p.name or n}"; }) packages;

        in
        {

          inherit packages apps;

          legacyPackages = project;

          # Built by `nix build .`
          defaultPackage = packages.ogmios;

          # Run by `nix run .`
          defaultApp = apps.ogmios;
        }
      ) // {
      inherit overlay nixosModule;
      nixosModules.ogmios = nixosModule;
      hydraJobs = self.packages // {
        required = with self.legacyPackages.${lib.head supportedSystems}.pkgs; releaseTools.aggregate {
          name = "github-required";
          meta.description = "All jobs required to pass CI";
          constituents = lib.collect lib.isDerivation self.packages ++ lib.singleton
            (writeText "forceNewEval" self.rev or "dirty");
        };
      };
    };

  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys = [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
    allow-import-from-derivation = true;
  };
}
