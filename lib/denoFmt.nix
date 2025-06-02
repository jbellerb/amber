{ lib, mkDenoDerivation }:

let
  inherit (lib) concatStringsSep;

in
{
  pname,
  ignore ? [ ],
  ...
}@args:
let
  ignoreList = concatStringsSep "," ([ "deno.json" ] ++ ignore);
in
mkDenoDerivation (
  args
  // {
    pname = "${pname}-fmt";

    buildPhaseCommand = ''
      deno fmt --config "$denoConfigVendored" --check --ignore="${ignoreList}" .
    '';

    installPhaseCommand = ''
      touch "$out"
    '';
  }
)
