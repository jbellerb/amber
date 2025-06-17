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
          ) systems
        );

      devHash = "sha256-5SMnjlxGjvB/IQrsIjRdMD3mhWi3W0mk6TjALs/mv2w=";
      devPath = "path:${./dev}?narHash=${devHash}";
      devInputs = (builtins.getFlake (builtins.unsafeDiscardStringContext devPath)).inputs;

      mkTreefmt = lib.flip devInputs.treefmt-nix.lib.evalModule (
        { pkgs, ... }:
        {
          projectRootFile = "flake.nix";
          programs.deno.enable = true;
          programs.nixfmt.enable = true;
          settings.global.excludes = [
            ".envrc"
            "README.md"
            "LICENSE"
            "src/module_graph.json"
          ];
        }
      );
    in
    {
      mkLib = pkgs: import ./lib/default.nix { inherit (pkgs) lib newScope; };
    }
    // (perSystem (
      { pkgs, system }:
      let
        denoLib = self.mkLib pkgs;
        treefmt = mkTreefmt pkgs;
      in
      {
        packages."${system}" = {
          graphAnalyzer = denoLib.graphAnalyzer;

          # See src/BOOTSTRAP.md for bootstrapping instructions
          # bootstrap = pkgs.callPackage ./src/bootstrap.nix { };
        };

        devShells."${system}".default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.deno
            self.packages."${system}".graphAnalyzer
            treefmt.config.build.wrapper
          ];
        };

        formatter."${system}" = treefmt.config.build.wrapper;

        checks."${system}" =
          let
            analyzerArgs = {
              inherit (denoLib.graphAnalyzer) pname version src;
            };
          in
          {
            formatting = treefmt.config.build.check self;
            graphAnalyzer-lint = denoLib.denoLint analyzerArgs;
            graphAnalyzer-check = denoLib.denoCheck analyzerArgs;
          };
      }
    ));
}
