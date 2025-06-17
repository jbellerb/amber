{
  lib,
  fetchurl,
  deno,
}:

{ url, hash, ... }@args:
let
  userAgent = "Deno/${deno.version}";
in
fetchurl (
  args
  // {
    name = lib.strings.sanitizeDerivationName url;
    inherit url hash;

    curlOptsList = [
      "--user-agent"
      userAgent
    ];
  }
)
