# Amber

Freeze your [Deno](https://deno.com/) (and [Fresh](https://fresh.deno.dev/)!)
projects with automatic, reproducible dependency vendoring. Powered by
[Nix](https://nixos.org/).

> [!WARNING] Deno 1.x only. Almost all of this code is extracted from the build
> system for [manivilization](https://github.com/jbellerb/manivilization/).
> While a goal of that project was to provide a generic base for my other
> projects, my use cases may not match yours. NodeJS and NPM support
> intentionally omitted for ideological reasons.

## Features

- Fetch URL imports and [JSR](https://jsr.io/) packages from Nix expressions
  - Reproducibility is guaranteed by Deno's
    [lock file](https://docs.deno.com/runtime/fundamentals/modules/#integrity-checking-and-lock-files)
  - Only the files actually imported by your app will be downloaded
- Run Deno apps within Nix
  - Wrap your app and its dependencies into a standalone script with all
    TypeScript pre-compiled
  - Special wrapper for bundling websites that use Fresh
    - Fresh sites can easily be packaged in a minimal Docker container with
      [`dockerTools`](https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-dockerTools)
  - Include extra dependencies outside of JS (CSS files, Wasm, etc.)
- `deno fmt`, `deno lint`, and `deno check` checks for Nix-powered CI

### Why use Amber?

Amber makes packaging Deno easy. Through static analysis of your app,
dependencies are fetched automatically (dynamic dependencies can be specified
separately). Everything is matched against the cryptographic hashes stored in
the project lock file. A build is guaranteed to match any other build of the
same commit, or it will fail.

Since dependencies are pre-downloaded and pre-compiled, startup times are often
near-instant. The website Amber was built for (~6k lines of TypeScript, 5.3MB of
dependencies), as a Docker container on fly.io, boots and is able to respond to
requests in 2 seconds.

### Why not to use Amber?

Amber is **slow**. This project predates
[dynamic derivations](https://github.com/NixOS/rfcs/blob/master/rfcs/0092-plan-dynamism.md),
and makes heavy use of
[fixed outputs](https://nix.dev/manual/nix/2.24/language/advanced-attributes.html#adv-attr-outputHash)
and
[importing from derivations](https://nix.dev/manual/nix/2.26/language/import-from-derivation).
Nix [heavily discourages](https://github.com/NixOS/nix/issues/2270) this and
there are serious performance implications. Significant effort is put into
parallelizing fetches and keeping Nix busy while the Deno module graph is being
analyzed, but fundamentally Nix must pause at least once per level of external
import. Performance is especially poor when using JSR packages, due to the fact
their metadata is not stored in `deno.lock` and must be fetched from the web.
Caching massively helps, but large builds can take several minutes when run the
first time.

A lot has been written about the complexity of Nix. If you are not already
convinced of the value Nix provides in purity and reproducibility, Amber will
not change your mind.

## Getting Started

Amber is designed to be used as a flake. Your `flake.nix` should look something
like:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    amber.url = "github:jbellerb/amber";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
    in
    builtins.foldl' nixpkgs.lib.recursiveUpdate { } (
      builtins.map (system:
        let
          pkgs = import nixpkgs { inherit system; };
          denoLib = inputs.amber.mkLib pkgs;
        in
        {
          packages."${system}".default = denoLib.buildDenoScript {
            pname = "my-app";
            version = "1.0.0";

            src = nixpkgs.lib.cleanSource ./.;
          };
        }
      ) systems
    );
}
```

<br />

#### License

<sup>
Copyright (C) jae beller, 2024.
</sup>
<br />
<sup>
Released under the MIT License. See <a href="LICENSE">LICENSE</a> for more information.
</sup>
