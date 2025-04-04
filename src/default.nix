{ lib, buildDenoScript, vendorDenoDeps }:

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

in buildDenoScript {
  pname = "graph-analyzer";
  version = "0.1.0";

  inherit src;

  # bootstrap the analyzer by vendoring with precomputed module graph
  denoVendorDir = vendorDenoDeps {
    inherit src;
    denoModuleGraph = lib.importJSON "${src}/module_graph.json";
    extraImports = {
      "deno_graph/deno_graph_wasm_bg.wasm" = {
        url = "https://deno.land/x/deno_graph@0.69.6/deno_graph_wasm_bg.wasm";
        sha256 = "4c031e9511932456344ff236ae75f9978fc3d49a19254a23c785bd47b63fb333";
      };
    };
  };
}
