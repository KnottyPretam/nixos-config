{
  description = "Pretam's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Claude and ChatGPT ship official Linux builds but are not packaged in
    # nixpkgs (the `chatgpt` attr there is macOS-only). These community flakes
    # repack the vendors' own .deb releases. They are third-party and will break
    # if the vendors move their download URLs - if a rebuild ever fails here,
    # fall back to a Chromium web-app the way Grok is handled.
    claude-desktop = {
      url = "github:danielbodart/claude-desktop";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    chatgpt-desktop = {
      url = "github:danielbodart/chatgpt-desktop";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ nixpkgs, home-manager, ... }:
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        specialArgs = { inherit inputs; };

        modules = [
          ./configuration.nix

          home-manager.nixosModules.home-manager

          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";

            # Lets home.nix reach the claude-desktop / chatgpt-desktop inputs.
            home-manager.extraSpecialArgs = { inherit inputs; };

            home-manager.users.pretamc = import ./home.nix;
          }
        ];
      };
    };
}
