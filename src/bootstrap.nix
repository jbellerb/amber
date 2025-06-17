{
  lib,
  newScope,
  fetchurl,
  runCommandLocal,
  writeText,
}:

let
  inherit (lib) fileset importJSON;

  src = fileset.toSource {
    root = ./.;
    fileset = fileset.unions [
      ./deno.json
      ./deno.lock
      ./main.ts
    ];
  };

  denoConfigParsed = importJSON ./deno.json;
  denoConfigVendored = runCommandLocal "deno-config-vendored-dir" { } ''
    mkdir "$out"
    ln -s "${./vendor}" "$out/vendor"
    ln -s "${src}/deno.lock" "$out/deno.lock"
    cat > "$out/deno.json" <<'EOF'
    ${builtins.toJSON (
      denoConfigParsed
      // {
        imports = denoConfigParsed.imports // {
          "@deno/graph/deno_graph_wasm_bg.wasm" = fetchurl {
            url = "https://jsr.io/@deno/graph/0.95.1/deno_graph_wasm_bg.wasm";
            hash = "sha256-NlefxeMIyI+3Gw6UunVZ7tb+6JtUq7wlUbXfNBlzksY=";
          };
          "import_map/import_map_bg.wasm" = fetchurl {
            url = "https://deno.land/x/import_map@v0.22.0/import_map_bg.wasm";
            hash = "sha256-vEJJoF5OVhmuj9Ys4vkne57/L6a6c/Ed4YKUaNxvFGg=";
          };
        };
      }
    )}
    EOF
  '';

  scope = import ../lib/default.nix { inherit lib newScope; };
  denoLib = scope.overrideScope (
    final: prev: {
      graphAnalyzer = prev.buildDenoScript {
        pname = "graph-analyzer";
        version = "0.0.0-bootstrap";

        inherit src;

        denoVendorDir = "${denoConfigVendored}/vendor";
        denoConfigVendored = "${denoConfigVendored}/deno.json";
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
