{
  lib,
  downloadJSRPackage,
  downloadRemoteModule,
}:

{ specifier, denoLockParsed }:
let
  packages =
    if denoLockParsed.version == "3" then
      denoLockParsed.packages or { }
    else
      throw "Deno lock file has an unsupported version: ${denoLockParsed.version}";
  remote =
    if denoLockParsed.version == "3" then
      denoLockParsed.remote or { }
    else
      throw "Deno lock file has an unsupported version: ${denoLockParsed.version}";

  scheme = builtins.head (builtins.match "^([A-Za-z][+\-.A-Za-z]*:).*$" specifier);
in
if scheme == "file:" then
  throw "Local specifiers can't be resolved: ${specifier}"
else if scheme == "http:" || scheme == "https:" then
  let
    split = builtins.match "^https?://jsr.io/([^/]+/[^/]+)/([^/]+)(/.+)$" specifier;
    parentSpecifier = "${builtins.elemAt split 0}@${builtins.elemAt split 1}";
    parentPackage = downloadJSRPackage {
      specifier = "jsr:${parentSpecifier}";
      integrity = packages.jsr.${parentSpecifier}.integrity;
    };
  in
  if split == null then
    downloadRemoteModule {
      url = specifier;
      sha256 = remote.${specifier};
    }
  else
    parentPackage.files.${builtins.elemAt split 2}
else if scheme == "jsr:" then
  let
    split = builtins.match "^jsr:/?(@[^@/]+/[^@/]+@[^@/]+)(/.+)?$" specifier;
    resolvedSpecifier = packages.specifiers.${"jsr:${builtins.elemAt split 0}"};
    entrypoint = "." + (builtins.toString (builtins.elemAt split 1));
    package = downloadJSRPackage {
      specifier = resolvedSpecifier;
      integrity = packages.jsr.${lib.removePrefix "jsr:" resolvedSpecifier}.integrity;
    };
  in
  package.files.${lib.removePrefix "." package.exports.${entrypoint}}
  // {
    packageMeta = package.meta;
  }
else
  throw "Cannot resolve unrecognized specifier: ${specifier}"
