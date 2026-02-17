flake:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.sure;

  surePackage = cfg.package;

  # Build the environment variable set for systemd services
  # RAILS_ROOT points to stateDir so Rails and gems write there, not the read-only Nix store
  sureEnv =
    {
      RAILS_ENV = "production";
      RAILS_LOG_TO_STDOUT = "1";
      NIXOS = "1";
      RAILS_ROOT = cfg.stateDir;
      SELF_HOSTED = lib.boolToString cfg.selfHosted;
      PORT = toString cfg.port;
      DB_HOST = cfg.database.host;
      DB_PORT = toString cfg.database.port;
      POSTGRES_DB = cfg.database.name;
      POSTGRES_USER = cfg.database.user;
      RAILS_MAX_THREADS = toString cfg.puma.threads;
      WEB_CONCURRENCY = toString cfg.puma.workers;
      REDIS_URL = "redis://${cfg.redis.host}:${cfg.redis.port}/1";
    }
    // cfg.environment;


  # Working directory setup script
  setupScript = pkgs.writeShellScript "sure-setup" ''
    set -euo pipefail

    STATE_DIR="${cfg.stateDir}"

    # Symlink app code from the Nix store
    for item in ${surePackage}/share/sure/*; do
      name="$(basename "$item")"
      # Skip directories we manage as writable
      case "$name" in
        tmp|log|storage|db) continue ;;
      esac
      ln -sfn "$item" "$STATE_DIR/$name"
    done

    # Create writable directories
    mkdir -p "$STATE_DIR/tmp/pids"
    mkdir -p "$STATE_DIR/tmp/cache"
    mkdir -p "$STATE_DIR/tmp/sockets"
    mkdir -p "$STATE_DIR/tmp/mini_profiler"
    mkdir -p "$STATE_DIR/log"
    mkdir -p "$STATE_DIR/storage"
    mkdir -p "$STATE_DIR/db"

    # Symlink db/ contents (schema, seeds, migrations) from Nix store, keep writable dirs
    if [ -d "${surePackage}/share/sure/db" ]; then
      for item in ${surePackage}/share/sure/db/*; do
        name="$(basename "$item")"
        ln -sfn "$item" "$STATE_DIR/db/$name"
      done
    fi

    # Bootsnap cache
    mkdir -p "$STATE_DIR/tmp/bootsnap-cache"

    # Ensure the sure user can write to tmp, log, storage, etc.
    chown -R sure:sure "$STATE_DIR"
  '';

  # Create pgcrypto extension as postgres superuser (app user lacks CREATE privilege)
  ensurePgcryptoScript = pkgs.writeShellScript "sure-ensure-pgcrypto" ''
    set -euo pipefail
    su postgres -c '${pkgs.postgresql}/bin/psql -d "${cfg.database.name}" -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pgcrypto"'
  '';

  # Database migration script
  # This script needs access to credentials and writable directories for Rails to boot
  migrateScript = pkgs.writeShellScript "sure-migrate" ''
    set -euo pipefail
    
    # Change to writable state directory (must be done before any Rails code runs)
    cd "${cfg.stateDir}"
    
    # Export writable directory paths to prevent gems from writing to Nix store
    export BOOTSNAP_CACHE_DIR="${cfg.stateDir}/tmp/bootsnap-cache"
    export TMPDIR="${cfg.stateDir}/tmp"
    export RAILS_TMP="${cfg.stateDir}/tmp"
    
    # Ensure Rails resolves root to stateDir (where config files are symlinked)
    # This prevents gems from writing to the read-only Nix store
    export RAILS_ROOT="${cfg.stateDir}"
    
    # Export credentials from LoadCredential (available in ExecStartPre)
    if [ -n "''${CREDENTIALS_DIRECTORY:-}" ]; then
      export SECRET_KEY_BASE="$(< "$CREDENTIALS_DIRECTORY/secret_key_base")"
      ${lib.optionalString (cfg.masterKeyFile != null) ''
        if [ -f "$CREDENTIALS_DIRECTORY/master_key" ]; then
          export RAILS_MASTER_KEY="$(< "$CREDENTIALS_DIRECTORY/master_key")"
        fi
      ''}
      ${lib.optionalString (cfg.database.passwordFile != null) ''
        if [ -f "$CREDENTIALS_DIRECTORY/db_password" ]; then
          export POSTGRES_PASSWORD="$(< "$CREDENTIALS_DIRECTORY/db_password")"
        fi
      ''}
    fi
    
    ${surePackage}/bin/sure-rake db:prepare
  '';

in
{
  options.services.sure = {
    enable = lib.mkEnableOption "Sure personal finance application";

    package = lib.mkOption {
      type = lib.types.package;
      default = flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "sure.packages.\${stdenv.hostPlatform.system}.default";
      description = "The Sure package to use.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sure";
      description = "Directory for Sure runtime state (logs, tmp, storage).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port for the Puma web server to listen on.";
    };

    selfHosted = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to run in self-hosted mode.";
    };

    secretKeyBaseFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing the SECRET_KEY_BASE value.
        Generate one with: openssl rand -hex 64
      '';
    };

    masterKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional path to the Rails master.key file for credentials decryption.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''
        {
          APP_DOMAIN = "finance.example.com";
          OPENAI_ACCESS_TOKEN = "sk-...";
        }
      '';
      description = "Additional environment variables to pass to Sure.";
    };

    # ---------- Database ----------

    database = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "/run/postgresql";
        description = ''
          PostgreSQL host. Use a socket path (e.g. /run/postgresql) for local
          peer-authenticated connections, or a hostname for TCP.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port (only used for TCP connections).";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "sure";
        description = "PostgreSQL database name.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "sure";
        description = "PostgreSQL user.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a file containing the database password.
          Not needed when using local peer authentication.
        '';
      };

      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to create the PostgreSQL database and user locally.";
      };
    };

    # ---------- Redis ----------

    redis = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "Redis connection URL.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
        description = "Redis connection port";
      };

      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable a local Redis server.";
      };
    };

    # ---------- Puma ----------

    puma = {
      workers = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = "Number of Puma worker processes.";
      };

      threads = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Number of threads per Puma worker.";
      };
    };

    # ---------- Sidekiq ----------

    sidekiq = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable the Sidekiq background worker.";
      };

      concurrency = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Number of Sidekiq threads.";
      };
    };
  };

  config = lib.mkIf cfg.enable {

    # ---- PostgreSQL ----
    services.postgresql = lib.mkIf cfg.database.createLocally {
      enable = true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensureDBOwnership = true;
        }
      ];
    };

    # ---- Redis ----
    services.redis.servers.sure = lib.mkIf cfg.redis.createLocally {
      enable = true;
      port = cfg.redis.port;
    };

    # ---- System user ----
    users.users.sure = {
      isSystemUser = true;
      group = "sure";
      home = cfg.stateDir;
      createHome = true;
    };
    users.groups.sure = { };

    # ---- Puma systemd service ----
    systemd.services.sure-puma = {
      description = "Sure - Puma Web Server";
      wantedBy = [ "multi-user.target" ];
      after =
        [ "network.target" ]
        ++ lib.optional cfg.database.createLocally "postgresql.service"
        ++ lib.optional cfg.redis.createLocally "redis-sure.service";
      requires =
        lib.optional cfg.database.createLocally "postgresql.service"
        ++ lib.optional cfg.redis.createLocally "redis-sure.service";

      environment = sureEnv // {
        BOOTSNAP_CACHE_DIR = "${cfg.stateDir}/tmp/bootsnap-cache";
        TMPDIR = "${cfg.stateDir}/tmp";
        RAILS_TMP = "${cfg.stateDir}/tmp";
        RAILS_FORCE_SSL = "false";
        RAILS_ASSUME_SSL = "false";
      };

      path = [ surePackage pkgs.postgresql ];

      serviceConfig = {
        Type = "simple";
        User = "sure";
        Group = "sure";
        WorkingDirectory = cfg.stateDir;

        ExecStartPre = [
          "+${setupScript}"
          migrateScript
        ];

        Restart = "on-failure";
        RestartSec = "10s";

        # Load secret key base from file
        LoadCredential = [
          "secret_key_base:${cfg.secretKeyBaseFile}"
        ] ++ lib.optional (cfg.masterKeyFile != null) "master_key:${cfg.masterKeyFile}"
          ++ lib.optional (cfg.database.passwordFile != null) "db_password:${cfg.database.passwordFile}";

        # Sandboxing
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ cfg.stateDir ];

        StateDirectory = "sure";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "sure";
        RuntimeDirectoryMode = "0750";
      };

      # Export secrets as environment variables from LoadCredential
      script = ''
        export SECRET_KEY_BASE="$(< "$CREDENTIALS_DIRECTORY/secret_key_base")"
        ${lib.optionalString (cfg.masterKeyFile != null) ''
          export RAILS_MASTER_KEY="$(< "$CREDENTIALS_DIRECTORY/master_key")"
        ''}
        ${lib.optionalString (cfg.database.passwordFile != null) ''
          export POSTGRES_PASSWORD="$(< "$CREDENTIALS_DIRECTORY/db_password")"
        ''}
        exec ${surePackage}/bin/sure-bundle exec puma -C ${cfg.stateDir}/config/puma.rb
      '';
    };

    # ---- Sidekiq systemd service ----
    systemd.services.sure-sidekiq = lib.mkIf cfg.sidekiq.enable {
      description = "Sure - Sidekiq Background Worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "sure-puma.service" ];
      requires = [ "sure-puma.service" ];

      environment = sureEnv // {
        BOOTSNAP_CACHE_DIR = "${cfg.stateDir}/tmp/bootsnap-cache";
        TMPDIR = "${cfg.stateDir}/tmp";
        RAILS_TMP = "${cfg.stateDir}/tmp";
        RAILS_MAX_THREADS = toString cfg.sidekiq.concurrency;
      };

      path = [ surePackage pkgs.postgresql ];

      serviceConfig = {
        Type = "simple";
        User = "sure";
        Group = "sure";
        WorkingDirectory = cfg.stateDir;

        Restart = "on-failure";
        RestartSec = "10s";

        LoadCredential = [
          "secret_key_base:${cfg.secretKeyBaseFile}"
        ] ++ lib.optional (cfg.masterKeyFile != null) "master_key:${cfg.masterKeyFile}"
          ++ lib.optional (cfg.database.passwordFile != null) "db_password:${cfg.database.passwordFile}";

        # Sandboxing
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ cfg.stateDir ];
      };

      script = ''
        export SECRET_KEY_BASE="$(< "$CREDENTIALS_DIRECTORY/secret_key_base")"
        ${lib.optionalString (cfg.masterKeyFile != null) ''
          export RAILS_MASTER_KEY="$(< "$CREDENTIALS_DIRECTORY/master_key")"
        ''}
        ${lib.optionalString (cfg.database.passwordFile != null) ''
          export POSTGRES_PASSWORD="$(< "$CREDENTIALS_DIRECTORY/db_password")"
        ''}
        exec ${surePackage}/bin/sure-bundle exec sidekiq -C ${cfg.stateDir}/config/sidekiq.yml
      '';
    };
  };
}
