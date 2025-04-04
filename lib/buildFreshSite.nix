{ fetchFromGitHub, mkDenoDerivation, esbuild }:

{ entrypoints ? [ ], extraImports ? null, ... }@args:
  let
    # esbuild binary version must be compatible with what's used by Fresh. as
    # of writing, Fresh uses esbuild 0.20.2.
    esbuild19 = esbuild.overrideAttrs (final: prev: rec {
      version = "0.20.2";
      src = fetchFromGitHub {
        owner = "evanw";
        repo = "esbuild";
        rev = "v${version}";
        hash = "sha256-h/Vqwax4B4nehRP9TaYbdixAZdb1hx373dNxNHvDrtY=";
      };
    });

  in mkDenoDerivation (args // {
    outputs = [ "out" "cache" ];
    denoCacheDir = "$cache";

    entrypoints = args.entrypoints ++ [
      "main.ts"
      "dev.ts"
      # These get imported dynamically so they aren't included in the static
      # module graph and would be skipped. deno vendor has this issue too.
      "https://deno.land/x/fresh@1.6.8/src/runtime/entrypoints/deserializer.ts"
      "https://deno.land/x/fresh@1.6.8/src/runtime/entrypoints/main.ts"
      "https://deno.land/x/fresh@1.6.8/src/runtime/entrypoints/signals.ts"
    ];

    preBuild = "export ESBUILD_BINARY_PATH=${esbuild19}/bin/esbuild";
    buildPhaseCommand = ''
      # esbuild_deno_loader doesn't respect the --config argument so I have
      # to copy the config here
      cp "$denoConfigVendored" deno.json
      deno run -A --no-remote dev.ts build
    '';

    installPhaseCommand = ''
      cp -r . "$out"
      # Copy the config to the out directory for convenience when running the
      # output derivation
      cp "$denoConfigVendored" "$out/deno.json"

      # TODO: report Fresh bug where built static files are ignored if there is
      # no static directory in the base directory.
      mkdir -p "$out/static"
    '';
  })
