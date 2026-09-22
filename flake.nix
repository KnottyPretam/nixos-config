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
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

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
                    }).claude-code;
                })
              ];
            }
          )

          home-manager.nixosModules.home-manager

          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";

            home-manager.users.pretamc = import ./home.nix;
          }
        ];
      };
    };
}
