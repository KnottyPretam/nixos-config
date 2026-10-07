{
  description = "Pretam's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Claude Code only, on its own input, so it can be updated without moving
    # the rest of the system:
    #   nix flake update nixpkgs-claude && sudo nixos-rebuild switch --flake .#nixos
    # Deliberately NOT `inputs.nixpkgs.follows` - following would defeat the
    # point and pin it back to the main nixpkgs.
    nixpkgs-claude.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, nixpkgs-claude, home-manager, ... }:
    let
      # Who and where this is - see machine.nix. Passed to both the system and
      # the Home Manager modules so the username lives in exactly one place.
      machine = import ./machine.nix;
    in
    {
      # Named after the host, so a second machine adds its own output rather
      # than overwriting this one. Build with .#${machine.hostName}.
      nixosConfigurations.${machine.hostName} = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        specialArgs = { inherit machine; };

        modules = [
          ./configuration.nix

          # Take claude-code from its own input. Everything else still comes
          # from nixpkgs.
          (
            { ... }:
            {
              nixpkgs.overlays = [
                (final: prev: {
                  # Imported with this system's nixpkgs config rather than
                  # taken from legacyPackages, which carries its own default
                  # config - and so would reject claude-code as unfree.
                  claude-code =
                    (import nixpkgs-claude {
                      inherit (prev) system config;
                    }).claude-code.override {
                      # nixpkgs is behind (2.1.278) and Opus 5.5 needs 2.1.280,
                      # so the release manifest is pinned here instead. It
                      # carries the version and the per-platform checksum, and
                      # is the package's own argument - no patching involved.
                      # Refresh with:
                      #   V=$(curl -s https://downloads.claude.ai/claude-code-releases/latest)
                      #   curl -s -o pkgs/claude-code-manifest.json \
                      #     "https://downloads.claude.ai/claude-code-releases/$V/manifest.zst.json"
                      # DELETE this override once nixpkgs ships >= 2.1.280, so
                      # claude-code goes back to tracking its input.
                      manifest = builtins.fromJSON (
                        builtins.readFile ./pkgs/claude-code-manifest.json
                      );
                    };
                })
              ];
            }
          )

          home-manager.nixosModules.home-manager

          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";

            # extraSpecialArgs, not specialArgs: the one above reaches the
            # SYSTEM modules, this one reaches home.nix.
            home-manager.extraSpecialArgs = { inherit machine; };

            home-manager.users.${machine.username} = import ./home.nix;
          }
        ];
      };
    };
}
