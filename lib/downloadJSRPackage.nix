{
  lib,
  fetchurl,
  downloadJSRPackage,
  downloadRemoteModule,
}:

{
  scope,
  name,
  version,
  integrity,
}:
let
  metaFile = fetchurl {
    name = "jsr-${scope}-${name}-${version}-meta.json";
    url = "https://jsr.io/@${scope}/${name}/${version}_meta.json";
    hash = builtins.convertHash {
      hash = integrity;
      toHashFormat = "sri";
      hashAlgo = "sha256";
    };

    passthru = {
      packageScope = scope;
      packageName = name;
      packageVersion = version;
    };
  };
  meta = lib.importJSON metaFile;

  traversePath =
    from: rel:
    let
      fromParts = lib.splitString "/" from;
      relParts = lib.splitString "/" rel;
    in
    lib.concatStringsSep "/" (
      lib.foldl' (
        acc: component:
        if component == "" || component == "." then
          acc
        else if component == ".." then
          lib.init acc
        else
          acc ++ [ component ]
      ) (lib.init fromParts) relParts
    );

  downloadPath =
    { path, checksum }:
    downloadRemoteModule {
      url = "https://jsr.io/@${scope}/${name}/${version}${path}";
      hash = builtins.convertHash {
        hash = lib.removePrefix "sha256-" checksum;
        toHashFormat = "sri";
        hashAlgo = "sha256";
      };

      passthru = {
        moduleSiblings = builtins.foldl' (
          acc: dep:
          if !(lib.hasPrefix "." dep.specifier) then
            acc
          else
            let
              depPath = traversePath path dep.specifier;
            in
            acc
            ++ (lib.singleton (downloadPath {
              path = depPath;
              checksum = meta.manifest.${depPath}.checksum;
            }))
        ) [ ] ((meta.moduleGraph2 or meta.moduleGraph1).${path}.dependencies or [ ]);
      };
    };
in
{
  files = lib.mapAttrs (
    path: info:
    downloadPath {
      inherit path;
      checksum = info.checksum;
    }
  ) meta.manifest;
  exports = meta.exports;
  meta = metaFile;
}
