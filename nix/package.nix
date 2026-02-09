{
  lib,
  stdenv,
  rubyEnv,
  ruby,
  vips,
  postgresql,
  libyaml,
  shared-mime-info,
  makeWrapper,
  tailwindcss_4
}:

let
  src = lib.cleanSourceWith {
    src = lib.cleanSource ../.;
    filter =
      name: type:
      let
        baseName = builtins.baseNameOf name;
      in
      !(builtins.elem baseName [
        ".git"
        ".github"
        ".devcontainer"
        "node_modules"
        "builds"
        "tmp"
        "log"
        "storage"
        "nix"
        "flake.nix"
        "flake.lock"
        ".env"
        ".env.local"
        ".env.test"
        "mobile"
        "charts"
        ".cursor"
      ]);
  };
in

stdenv.mkDerivation {
  pname = "sure";
  version = "0.1.0";

  inherit src;

  nativeBuildInputs = [
    makeWrapper
    rubyEnv
    ruby
  ];

  buildInputs = [
    vips
    postgresql.lib
    libyaml
    shared-mime-info
  ];

  buildPhase = ''
    runHook preBuild

    # Set up environment for asset precompilation
    export HOME=$(mktemp -d)
    export RAILS_ENV=production
    export SECRET_KEY_BASE_DUMMY=1
    export BUNDLE_GEMFILE="$PWD/Gemfile"
    export TAILWINDCSS_INSTALL_DIR="${tailwindcss_4}/bin";
    export FREEDESKTOP_MIME_TYPES_PATH="${shared-mime-info}/share/mime/packages/freedesktop.org.xml"

    # Create writable tmp and asset build directories
    mkdir -p tmp/{pids,cache,sockets}
    mkdir -p log

    ${rubyEnv}/bin/bundle exec rails assets:precompile

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/sure
    cp -r . $out/share/sure/

    # Remove build artifacts not needed at runtime
    rm -rf $out/share/sure/tmp
    rm -rf $out/share/sure/log
    rm -rf $out/share/sure/storage
    rm -rf $out/share/sure/test
    rm -rf $out/share/sure/spec
    rm -rf $out/share/sure/.env*

    # Create required directory stubs
    mkdir -p $out/share/sure/tmp/{pids,cache,sockets}
    mkdir -p $out/share/sure/log

    # Create wrapper scripts
    mkdir -p $out/bin

    makeWrapper ${rubyEnv}/bin/bundle $out/bin/sure-bundle \
      --set BUNDLE_GEMFILE "$out/share/sure/Gemfile" \
      --prefix PATH : "${
        lib.makeBinPath [
          vips
          postgresql.lib
        ]
      }" \
      --set FREEDESKTOP_MIME_TYPES_PATH "${shared-mime-info}/share/mime/packages/freedesktop.org.xml"

    makeWrapper ${rubyEnv}/bin/bundle $out/bin/sure-rails \
      --set BUNDLE_GEMFILE "$out/share/sure/Gemfile" \
      --add-flags "exec rails" \
      --prefix PATH : "${
        lib.makeBinPath [
          vips
          postgresql.lib
        ]
      }" \
      --set FREEDESKTOP_MIME_TYPES_PATH "${shared-mime-info}/share/mime/packages/freedesktop.org.xml"

    makeWrapper ${rubyEnv}/bin/bundle $out/bin/sure-rake \
      --set BUNDLE_GEMFILE "$out/share/sure/Gemfile" \
      --add-flags "exec rake" \
      --prefix PATH : "${
        lib.makeBinPath [
          vips
          postgresql.lib
        ]
      }" \
      --set FREEDESKTOP_MIME_TYPES_PATH "${shared-mime-info}/share/mime/packages/freedesktop.org.xml"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Sure - personal finance application";
    license = licenses.agpl3Only;
    platforms = platforms.linux ++ platforms.darwin;
  };
}
