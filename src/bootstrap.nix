{
  lib,
  newScope,
  writeText,
}:

let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./deno.json
      ./deno.lock
      ./main.ts
    ];
  };

  scope = import ../lib/default.nix { inherit lib newScope; };
  denoLib = scope.overrideScope (
    final: prev: {
      graphAnalyzer = prev.buildDenoScript {
        pname = "graph-analyzer";
        version = "0.0.0-bootstrap";

        inherit src;

        denoVendorDir = ./vendor;
      };
    }
  );

  graph = denoLib.buildModuleGraph {
    denoConfig = "${src}/deno.json";
    denoLock = "${src}/deno.lock";
    rootModules = [ "${src}/main.ts" ];
  };
in
writeText "module_graph.json" (builtins.toJSON { inherit (graph) modules redirects roots; })
