{
  lib,
  buildDenoScript,
  vendorDenoDeps,
}:

let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./deno.json
      ./deno.lock
      ./main.ts
      ./module_graph.json
    ];
  };
in
buildDenoScript {
  pname = "graph-analyzer";
  version = "0.2.0";

  inherit src;

  # bootstrap the analyzer by vendoring with precomputed module graph
  denoVendorDir = vendorDenoDeps {
    inherit src;
    denoModuleGraph = lib.importJSON "${src}/module_graph.json";
    extraImports = {
      "@deno/graph/deno_graph_wasm_bg.wasm" = {
        url = "https://jsr.io/@deno/graph/0.95.1/deno_graph_wasm_bg.wasm";
        hash = "sha256-NlefxeMIyI+3Gw6UunVZ7tb+6JtUq7wlUbXfNBlzksY=";
      };
      "import_map/import_map_bg.wasm" = {
        url = "https://deno.land/x/import_map@v0.22.0/import_map_bg.wasm";
        hash = "sha256-vEJJoF5OVhmuj9Ys4vkne57/L6a6c/Ed4YKUaNxvFGg=";
      };
    };
  };
}
