{ pkgs }:

{
  pg = attrs: {
    buildInputs = [ pkgs.postgresql pkgs.postgresql.lib ];
    nativeBuildInputs = [ pkgs.pkg-config ];
  };

  nokogiri = attrs: {
    buildInputs = with pkgs; [
      zlib
      libiconv
      libxml2
      libxslt
    ];
    nativeBuildInputs = [ pkgs.pkg-config ];
  };

  bcrypt = attrs: {
    buildInputs = [ pkgs.openssl ];
  };

  ruby-vips = attrs: {
    buildInputs = [ pkgs.vips ];
    nativeBuildInputs = [ pkgs.pkg-config ];
  };

  redcarpet = attrs: {
    buildInputs = [ pkgs.which ];
  };

  racc = attrs: {
    buildInputs = [ pkgs.bison ];
  };

  psych = attrs: {
    buildInputs = [ pkgs.libyaml ];
    nativeBuildInputs = [ pkgs.pkg-config ];
  };

  puma = attrs: {
    buildInputs = [ pkgs.openssl ];
    nativeBuildInputs = [ pkgs.pkg-config ];
  };

  ffi = attrs: {
    buildInputs = [ pkgs.libffi ];
    nativeBuildInputs = [ pkgs.pkg-config ];
  };
}
