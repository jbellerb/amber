# Bootstrap

Amber uses this script to collect which modules are necessary for running a
given program. Because this script also runs in Deno, a list of its modules
needs to be pre-generated and checked into the repo. See
[default.nix](./default.nix) for how to build a Deno script with a pre-generated
JSON module graph.

To build this graph for the first time, or to update it if the script is
changed, `deno vendor` can mostly be used to prepare a vendor directory that can
be loaded by Nix.

## Vendoring dependencies

First, run `deno vendor main.ts` in this directory. A `vendor` directory with
most of the necessary JavaScript dependencies will be created, and `deno.json`
will be modified to point to it. Revert the changes to `deno.json`, since Nix
will handle mapping to a vendored set of dependencies for us.

Since the `deno_graph` module uses a WebAssembly binary for it's graph logic,
this will need to be added alongside the JS that Deno has already vendored for
us. Download `deno_graph_wasm_bg.wasm` and place it in
`vendor/deno.land/x/deno_graph@version/`. After that, edit
`vendor/import_map.json` to point to the binary like:

```diff
 {
   "imports": {
     ...
     "$std/path/posix/to_file_url.ts": "./deno.land/std@0.220.1/path/posix/to_file_url.ts",
     "deno_graph/mod.ts": "./deno.land/x/deno_graph@0.69.6/mod.ts",
+    "deno_graph/deno_graph_wasm_bg.wasm": "./deno.land/x/deno_graph@0.69.6/deno_graph_wasm_bg.wasm",
     "import-maps/parser.js": "./esm.sh/gh/WICG/import-maps@abc4c6b/reference-implementation/lib/parser.js",
     ...
```

## Generating the graph

With the vendor directory prepared, `bootstrap.nix` can be used to produce a
module graph. To make sure the correct Deno version is used, it's best if this
is run in the context of the project flake. So Nix can see the vendor directory,
add it to the index with `git add --intent-to-add`. After that, uncomment the
bootstrap package in `flake.nix` and run `nix build .#bootstrap`.

The bootstrap program will overlay Amber's package set with a version of
`graph-analyzer` using the `vendor/` directory, and then run `buildModuleGraph`
on the original `graph-analyzer`. After successfully building, a complete
`module_graph.json` should be symlinked into the root of the directory as
`result`. Copy that into `src/`. Finally, clean up by deleting and unstaging
`vendor/`, and commenting out the bootstrap package in `flake.nix`.
