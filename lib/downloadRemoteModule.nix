{ lib, fetchurl, deno }:

{ url, sha256, ... }@args:
  let
    userAgent = "Deno/${deno.version}";

  in fetchurl (args // {
    inherit url sha256;
    name = lib.strings.sanitizeDerivationName url;

    curlOptsList = [ "--user-agent" userAgent ];
  })
