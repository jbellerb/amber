{
  lib,
  downloadJSRPackage,
  downloadRemoteModule,
}:

let
  inherit (lib)
    defaultTo
    mapNullable
    removePrefix
    removeSuffix
    ;

  parsePackage =
    pkg:
    let
      split = builtins.match "(jsr):/?(@([^@/]+)/)?([^@/]+)@([^@/]+)?(/.+)?" pkg;
      kind = builtins.elemAt split 0;
      scope = builtins.elemAt split 2;
      version = normalizeVersion (builtins.elemAt split 4);
    in
    if split == null || version == null then
      throw "Failed to parse package identifier: ${pkg}"
    else if kind == "jsr" && scope == null then
      throw "JSR packages must always have a scope: ${pkg}"
    else
      {
        inherit kind scope;
        name = builtins.elemAt split 3;
        inherit version;
        path = builtins.elemAt split 5;
      };

  normalizeVersion =
    let
      isWildcard = xr: xr == "*" || xr == "x" || xr == "X";
      readNumber = mapNullable (n: if isWildcard n then null else builtins.fromJSON n);
      showNumber = n: defaultTo "0" (mapNullable builtins.toString n);
      zeroVersion = {
        major = "0";
        minor = "0";
        patch = "0";
        qualifier = "";
      };
    in
    ver:
    let
      split = builtins.match "([~^])?([*0xX]|[1-9][0-9]*)(\.([*0xX]|[1-9][0-9]*)(\.([*0xX]|[1-9][0-9]*)(.*))?)?" ver;
      operator = builtins.elemAt split 0;
      major = readNumber (builtins.elemAt split 1);
      minor = readNumber (builtins.elemAt split 3);
      patch = readNumber (builtins.elemAt split 5);
      qualifier = defaultTo "" (builtins.elemAt split 6);

      high =
        if major == null then
          null
        else if operator == "~" then
          if minor == null then
            zeroVersion // { major = showNumber (major + 1); }
          else
            zeroVersion
            // {
              major = showNumber major;
              minor = showNumber (minor + 1);
            }
        else if operator == "^" then
          if major > 0 || minor == null then
            zeroVersion // { major = showNumber (major + 1); }
          else if minor > 0 || patch == null then
            zeroVersion // { minor = showNumber (minor + 1); }
          else
            zeroVersion // { patch = showNumber (patch + 1); }
        else
          {
            major = showNumber (if minor == null then major + 1 else major);
            minor = showNumber (mapNullable (n: if patch == null then n + 1 else n) minor);
            patch = showNumber patch;
            inherit qualifier;
          };

      low = {
        major = showNumber major;
        minor = showNumber minor;
        patch = showNumber patch;
        inherit qualifier;
      };

      lowFull = "${low.major}.${low.minor}.${low.patch}${low.qualifier}";
      highFull = "${high.major}.${high.minor}.${high.patch}${high.qualifier}";

    in
    if split == null then
      null
    else if high == null then
      "*"
    else if high == low then
      lowFull
    else if
      (high.patch == "0" && low.patch == "0")
      && low.qualifier == ""
      && (high.minor == "0" && low.minor == "0")
    then
      low.major
    else if
      (high.patch == "0" && low.patch == "0")
      && low.qualifier == ""
      && (high.major == low.major && high.minor != "0" && high.minor != low.minor)
    then
      "${low.major}.${low.minor}"
    else if
      high.qualifier == ""
      && high.major == low.major
      && (
        high.minor == low.minor && high.patch == low.patch && low.qualifier != ""
        || high.minor != low.minor && high.patch == "0"
      )
    then
      "~" + lowFull
    else if
      high.qualifier == ""
      && (
        low.major == "0" && high.minor == "0" && low.minor == "0" && high.patch != low.patch
        || low.major != "0" && high.major != low.major && high.minor == "0" && high.patch == "0"
      )
    then
      "^" + lowFull
    else
      ">=" + lowFull + " <" + highFull;

in

{ specifier, denoLockParsed }:
let
  lock =
    if denoLockParsed.version == "5" then
      denoLockParsed
    else
      throw "Deno lock file has an unsupported version: ${denoLockParsed.version}";

  packages = {
    jsr = lock.jsr or { };
    specifiers = lock.specifiers or { };
  };
  redirects = lock.redirects or { };
  remote = lock.remote or { };

  scheme = builtins.head (builtins.match "([A-Za-z][+\-.A-Za-z]*:).*" specifier);
in
if scheme == "file:" then
  throw "Local specifiers can't be resolved: ${specifier}"
else if scheme == "http:" || scheme == "https:" then
  let
    redirect = redirects."${specifier}" or null;
    url = if redirect == null then specifier else redirect;
    split = builtins.match "https://jsr.io/@([^/]+)/([^/]+)/([^/]+)(/.+)" url;
    scope = builtins.elemAt split 0;
    name = builtins.elemAt split 1;
    version = builtins.elemAt split 2;
    path = builtins.elemAt split 3;
    parentPackage = downloadJSRPackage {
      inherit scope name version;
      integrity = packages.jsr."@${scope}/${name}@${version}".integrity;
    };
  in
  if split == null then
    downloadRemoteModule {
      inherit url;
      hash = builtins.convertHash {
        hash = remote.${url};
        toHashFormat = "sri";
        hashAlgo = "sha256";
      };

      passthru = if redirect != null then { redirection = redirect; } else { };
    }
  else
    parentPackage.files.${path}
else if scheme == "jsr:" then
  let
    inherit (parsePackage specifier)
      scope
      name
      version
      path
      ;
    resolvedVersion = packages.specifiers."jsr:@${scope}/${name}@${version}";
    package = downloadJSRPackage {
      inherit scope name;
      version = resolvedVersion;
      integrity = packages.jsr."@${scope}/${name}@${resolvedVersion}".integrity;
    };
  in
  package.files.${removePrefix "." package.exports.${"." + (builtins.toString path)}}
  // {
    packageMeta = package.meta;
  }
else
  throw "Cannot resolve unrecognized specifier: ${specifier}"
