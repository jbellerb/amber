{
  lib,
  downloadJSRPackage,
  downloadRemoteModule,
}:

{ specifier, denoLockParsed }:
let
  lock =
    if denoLockParsed.version == "3" then
      denoLockParsed
    else
      throw "Deno lock file has an unsupported version: ${denoLockParsed.version}";

  packages = lock.packages or { };
  redirects = lock.redirects or { };
  remote = lock.remote or { };

  scheme = builtins.head (builtins.match "^([A-Za-z][+\-.A-Za-z]*:).*$" specifier);
in
if scheme == "file:" then
  throw "Local specifiers can't be resolved: ${specifier}"
else if scheme == "http:" || scheme == "https:" then
  let
    redirect = redirects."${specifier}" or null;
    url = if redirect == null then specifier else redirect;
    split = builtins.match "^https?://jsr.io/([^/]+/[^/]+)/([^/]+)(/.+)$" url;
    parentSpecifier = "${builtins.elemAt split 0}@${builtins.elemAt split 1}";
    parentPackage = downloadJSRPackage {
      specifier = "jsr:${parentSpecifier}";
      integrity = packages.jsr.${parentSpecifier}.integrity;
    };
  in
  if split == null then
    downloadRemoteModule {
      inherit url;
      sha256 = remote.${url};

      passthru = if redirect != null then { redirection = redirect; } else { };
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
