# Bootstrap

Amber uses this script to collect which modules are necessary for running a
given program. Because this script also runs in Deno, a list of its modules
needs to be pre-generated and checked into the repo. See
[default.nix](./default.nix) for how to build a Deno script with a pre-generated
JSON module graph.

To build this graph for the first time, or to update it if the script is
changed, deno can mostly prepare a vendor directory that can be loaded by Nix.

## Vendoring dependencies

First, add the line `"vendor": true` to the bottom of `deno.json`. After
refreshing the module cache with `deno install --entrypoint main.ts`, a `vendor`
directory with most of the necessary JavaScript dependencies will be created.
Mappings to download any extra files the vendor process wouldn't normally pick
up are already hard-coded into `bootstrap.nix`. Even though the vendor directory
has been crated, Deno will only use it when the vendor field is set in
`deno.json`, so it must stay set during the entire bootstrap process.

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
`vendor/`, removing `"vendor": true` from `deno.json`, and commenting out the
bootstrap package in `flake.nix`.
