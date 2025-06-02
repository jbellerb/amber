{
  lib,
  fetchurl,
  deno,
}:

let
  inherit (lib.strings) sanitizeDerivationName;

in
{ url, hash, ... }@args:
let
  userAgent = "Deno/${deno.version}";
in
fetchurl (
  args
  // {
    inherit url hash;
    name = sanitizeDerivationName url;

    curlOptsList = [
      "--user-agent"
      userAgent
    ];
  }
)
