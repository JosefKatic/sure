ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# On NixOS the app directory is read-only (Nix store), so Bootsnap's cache
# must be redirected to a writable location via BOOTSNAP_CACHE_DIR.
if ENV["NIXOS"] == "1" && ENV["BOOTSNAP_CACHE_DIR"]
  require "bootsnap"
  Bootsnap.setup(cache_dir: ENV["BOOTSNAP_CACHE_DIR"])
else
  require "bootsnap/setup" # Speed up boot time by caching expensive operations.
end
