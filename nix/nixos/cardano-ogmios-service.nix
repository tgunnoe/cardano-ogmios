{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkOption types elem optionalString optionalAttrs;
  cfg = config.services.cardano-ogmios;
  logLevels = [ "Debug" "Info" "Notice" "Warning" "Error" "Off" ];
in
{
  options = {
    services.cardano-ogmios = {
      enable = mkEnableOption "enable the cardano-ogmios service";

      args = mkOption {
        description = "Command-line argument to launch ogmios.";
        type = types.separatedString " ";
        default = lib.concatStringsSep " " (
          # Only specify arguments if they have different value than the default:
          lib.optionals (cfg.hostAddr != "127.0.0.1") [
            "--host"
            (lib.escapeShellArg cfg.hostAddr)
          ] ++ lib.optionals (cfg.port != 1337) [
            "--port"
            (toString cfg.port)
          ] ++ lib.optionals (cfg.logLevel != "Info") [
            "--log-level"
            cfg.logLevel
          ] ++ lib.optionals (cfg.timeout != 90) [
            "--timeout"
            (toString cfg.timeout)
          ] ++ lib.optionals (cfg.maxInFlight != 1000) [
            "--max-in-flight"
            (toString cfg.maxInFlight)
          ] ++ [
            "--node-socket"
            "\"$CARDANO_NODE_SOCKET_PATH\""
            "--node-config"
            (toString cfg.nodeConfig)
          ]
          ++ lib.mapAttrsToList
            (name: level: "--log-level-${name}=${level}")
            cfg.logLevels
        );
      };

      rtsOpts = mkOption {
        type = types.separatedString " ";
        default = "-N2";
        example = "-M2G -N4";
        description = ''
          GHC runtime-system options for the cardano-wallet process.
          See https://downloads.haskell.org/ghc/8.10.7/docs/html/users_guide/runtime_control.html#setting-rts-options-on-the-command-line for documentation.
        '';
      };
      command = mkOption {
        type = types.str;
        internal = true;
        default = lib.concatStringsSep " " ([
          "${cfg.package}/bin/${cfg.package.exeName}"
          cfg.args
        ] ++ lib.optionals (cfg.rtsOpts != "") [ "+RTS" cfg.rtsOpts "-RTS" ]);
      };
      nodeConfig = mkOption {
        type = types.nullOr (types.either types.str types.path);
        description = "Path to cardano-node JSON/Yaml config file";
        default = null;
      };
      nodeSocket = mkOption {
        type = types.nullOr (types.either types.str types.path);
        description = "Path to cardano-node socket";
        default = null;
      };
      port = mkOption {
        type = types.int;
        default = 1337;
        description = ''
          The port number
        '';
      };
      hostAddr = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = ''
          The host address to bind to
        '';
      };
      timeout = mkOption {
        type = types.int;
        default = 90;
        description = ''
          Number of seconds of inactivity after which the
          server should close client connections.
        '';
      };
      maxInFlight = mkOption {
        type = types.int;
        default = 1000;
        description = ''
          Max number of ChainSync requests which can be
          pipelined at once. Only applies to the chain-sync
          protocol. (default: 1000)
        '';
      };
      logLevel = lib.mkOption {
        type = types.enum logLevels;
        default = "Info";
      };
      logLevels = mkOption {
        type = types.attrsOf (types.enum logLevels);
        default = { };
        description = ''
          For each tracer, minimum severity for a message to be logged, or
          "Off" to disable the tracer".
        '';
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.ogmios;
      };
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.services.cardano-ogmios = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = cfg.command;
        DynamicUser = true;
      };
      environment = {
        CARDANO_NODE_SOCKET_PATH = cfg.nodeSocket;
      };
    };
  };
}
