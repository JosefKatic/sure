{
  description = "Sure - personal finance app built with Ruby on Rails";

  nixConfig = {
    extra-substituters = "https://nixpkgs-ruby.cachix.org";
    extra-trusted-public-keys =
      "nixpkgs-ruby.cachix.org-1:vrcdi50fTolOxWCZZkw0jakOnUI1T19oYJ+PRYdK4SM=";
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    ruby-nix = {
      url = "github:inscapist/ruby-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    bundix = {
      url = "github:inscapist/bundix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fu.url = "github:numtide/flake-utils";

    bob-ruby = {
      url = "github:bobvanderlinden/nixpkgs-ruby";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      fu,
      ruby-nix,
      bundix,
      bob-ruby,
    }:
    fu.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ bob-ruby.overlays.default ];
        };

        rubyNix = ruby-nix.lib pkgs;

        # Import gemset and filter out incompatible libc platform targets.
        # Gems like tailwindcss-ruby, ffi, and nokogiri ship prebuilt binaries for
        # both glibc (gnu) and musl systems. auto-patchelf can only satisfy the
        # libc that matches the host, so we drop the other.
        # This keeps gemset.nix untouched after bundix regeneration.
        rawGemset =
          if builtins.pathExists ./nix/gemset.nix then import ./nix/gemset.nix else { };

        hostIsMusl = pkgs.stdenv.hostPlatform.isMusl;

        # On glibc hosts, drop musl targets; on musl hosts, drop gnu targets.
        isIncompatibleTarget = t:
          let
            target = t.target or "";
          in
          if hostIsMusl then
            builtins.match "!.*-musl" target != null
          else
            builtins.match ".*-musl" target != null;

        filterIncompatibleTargets = gem:
          gem
          // {
            targets = builtins.filter (t: !(isIncompatibleTarget t)) (gem.targets or [ ]);
          };

        gemset = builtins.mapAttrs (_: filterIncompatibleTargets) rawGemset;

        gemConfig = import ./nix/gem-config.nix { inherit pkgs; };

        ruby = pkgs."ruby-3.4.7";

        bundixCli = bundix.packages.${system}.default;

        # Ruby environment with all gems (ruby-nix returns { env, envMinimal, ruby, version })
        rubyNixEnv = rubyNix {
          inherit gemset ruby;
          name = "sure";
          gemConfig = pkgs.defaultGemConfig // gemConfig;
        };

        # The bundler environment derivation
        rubyEnv = rubyNixEnv.env;

        # The Rails application package
        sureApp = pkgs.callPackage ./nix/package.nix {
          inherit rubyEnv ruby;
        };

      in
      {
        packages = {
          default = sureApp;
          sure = sureApp;
        };

        devShells.default = pkgs.mkShell {
          buildInputs =
            [
              rubyEnv
              bundixCli
              ruby
            ]
            ++ (with pkgs; [
              postgresql
              redis
              libyaml
              vips
              pkg-config
              openssl
              zlib
              libiconv
              tailwindcss_4
            ]);

          shellHook = ''
            export TAILWINDCSS_INSTALL_DIR="${pkgs.tailwindcss_4}/bin";
            export FREEDESKTOP_MIME_TYPES_PATH="${pkgs.shared-mime-info}/share/mime/packages/freedesktop.org.xml"
          '';
        };
      }
    )
    // {
      nixosModules.default = import ./nix/module.nix self;

      overlays.default = final: prev: {
        sure = self.packages.${final.system}.default;
      };
    };
}
