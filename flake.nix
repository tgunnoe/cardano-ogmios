{
  description = "cardano-ogmios";

  inputs = {
    ogmios = {
      url = "github:CardanoSolutions/ogmios/v5.6.0";
      flake = false;
    };
    haskellNix = {
      # Haskell.nix update 2023/03/22
      url = "github:input-output-hk/haskell.nix/5c1276b35d8b4e8069bb065896d2e7dc022510b3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    CHaP = {
      # CHaP update 2023/03/23, repo branch
      url = "github:input-output-hk/cardano-haskell-packages/4a15403f6adbac6f47bcedbabac946f9c2636e59";
      flake = false;
    };
    iohkNix = {
      url = "github:input-output-hk/iohk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    tullia = {
      url = "github:input-output-hk/tullia";
      # XXX uncomment once our version of nixpkgs has this fix:
      # https://github.com/NixOS/nixpkgs/commit/3fae68b30cfc27a7df5beaf9aaa7cb654edd8403
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    config.url = "github:input-output-hk/empty-flake";
  };

  outputs = { self, ogmios, iohkNix, haskellNix, CHaP, nixpkgs, flake-utils, tullia, config, ... }:
    let
      inherit (nixpkgs) lib;
      inherit (flake-utils.lib) eachSystem mkApp flattenTree;
      inherit (iohkNix.lib) evalService;

      removeRecurse = lib.filterAttrsRecursive (n: _: n != "recurseForDerivations");

      supportedSystems = config.supportedSystems or (import ./nix/supported-systems.nix);

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
        } //
          tullia.fromSimple system (import ./nix/tullia.nix self system)
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
