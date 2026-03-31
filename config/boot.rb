ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# When running under systemd with LoadCredential, CREDENTIALS_DIRECTORY is set and *_FILE
# point to credential ids. Load those into the expected ENV vars so Rails and database.yml see them.
if (cred_dir = ENV["CREDENTIALS_DIRECTORY"]) && Dir.exist?(cred_dir)
  {
    "SECRET_KEY_BASE_FILE" => "SECRET_KEY_BASE",
    "RAILS_MASTER_KEY_FILE" => "RAILS_MASTER_KEY",
    "POSTGRES_PASSWORD_FILE" => "POSTGRES_PASSWORD"
  }.each do |file_var, env_var|
    next unless (cred_id = ENV[file_var])
    path = File.join(cred_dir, cred_id)
    ENV[env_var] = File.read(path).strip if File.file?(path)
  end
end

# On NixOS the app directory is read-only (Nix store), so Bootsnap's cache
# must be redirected to a writable location via BOOTSNAP_CACHE_DIR.
if ENV["NIXOS"] == "1" && ENV["BOOTSNAP_CACHE_DIR"]
  require "bootsnap"
  Bootsnap.setup(cache_dir: ENV["BOOTSNAP_CACHE_DIR"])
else
  require "bootsnap/setup" # Speed up boot time by caching expensive operations.
end
