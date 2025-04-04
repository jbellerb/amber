{
  description = "Automatic dependency vendoring for Deno";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        f:
        builtins.foldl' lib.recursiveUpdate { } (
          builtins.map (
            system:
            f {
              inherit system;
              pkgs = import nixpkgs { inherit system; };
            }
          )
        );

    in
    {
      mkLib = pkgs: import ./lib/default.nix { inherit (pkgs) lib newScope; };
    }
    // perSystem (
      { pkgs, system }:
      {
        packages."${system}" = {
          graphAnalyzer = (self.mkLib pkgs).graphAnalyzer;
        };
      }
    );
}
