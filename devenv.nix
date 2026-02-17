{
  pkgs,
  lib,
  config,
  ...
}:
{
  env = {
    SELF_HOSTED = true;
    PORT = 3000;
    TAILWINDCSS_INSTALL_DIR = "${pkgs.tailwindcss_4}/bin";
    DB_HOST = "127.0.0.1";
    REDISDATA = "${config.env.DEVENV_STATE}/redis";
  };

  # https://devenv.sh/languages/
  languages.ruby = {
    enable = true;
    versionFile = ./.ruby-version;
  };

  # https://devenv.sh/packages/
  packages = [
    pkgs.libyaml
    pkgs.openssl
    pkgs.watchman
  ]
  ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.libllvm ];

  # https://devenv.sh/services/
  services = {
    postgres = {
      enable = true;
      listen_addresses = config.env.DB_HOST;
    };
    redis = {
      enable = true;
    };
  };

  # https://devenv.sh/scripts/
  scripts = {
    setup.exec = "./bin/setup";
    dev.exec = "./bin/dev";
  };

  enterShell = ''
    export POSTGRES_USER=$USER
    export POSTGRES_PASSWORD=""
    bundle install
  '';
}
