{
  lib,
  fetchurl,
  deno,
}:

let
  inherit (lib.strings) sanitizeDerivationName;

in
{ url, ... }@args:
let
  userAgent = "Deno/${deno.version}";
in
fetchurl (
  args
  // {
    inherit url;
    name = sanitizeDerivationName url;

    curlOptsList = [
      "--user-agent"
      userAgent
    ];
  }
)
