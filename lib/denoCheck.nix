{ runCommandLocal, mkDenoDerivation, nix }:

{ pname, src, ... }@args:
  let
    computeHash = drv: builtins.readFile
      (runCommandLocal "compute-derivation-hash" { } ''
        ${nix}/bin/nix-hash --type sha256 "${drv}" > "$out"
      '');

  in mkDenoDerivation (args // rec {
    pname = "${args.pname}-check";

    # When Deno builds its lockfile, only executable JavaScript and TypeScript
    # are included, not separate type declarations in a .d.ts file. Normally
    # this isn't a problem as you really only need those during typechecking,
    # however I kind of need them during typechecking. Short of vendoring
    # everything, which I strongly don't want to do, my only option is to abuse
    # fixed-output derivations to grab them during the build. This heavily goes
    # against the spirit of nix, but since the real build is pure and this build
    # is purely to simplify CI checks, I'm fine with it for now. To make sure
    # the checks actually happen and aren't just skipped by nix caching, the
    # output hash needs to bind to the inputs. The easiest way I could come up
    # with was hashing the NAR of src in a separate derivation, setting the
    # output hash of this to the hash of that string, and then writing the hash
    # string after checks pass so final hash matches our prior hash of a hash.
    outputHashAlgo = "sha256";
    outputHash = builtins.hashString "sha256" "${computeHash src}-check";

    buildPhaseCommand = ''
      deno check ./{*,**/*}.ts
      deno check ./{*,**/*}.tsx
    '';

    installPhaseCommand = ''
      printf "${computeHash src}-check" > "$out"
    '';
  })
