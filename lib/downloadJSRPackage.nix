{
  lib,
  fetchurl,
  downloadRemoteModule,
}:

let
  inherit (lib)
    concatStringsSep
    foldl'
    hasPrefix
    importJSON
    init
    mapAttrs
    removePrefix
    singleton
    splitString
    ;

in
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
    sha256 = integrity;

    passthru = {
      packageScope = scope;
      packageName = name;
      packageVersion = version;
    };
  };
  meta = importJSON metaFile;

  traversePath =
    from: rel:
    let
      fromParts = splitString "/" from;
      relParts = splitString "/" rel;
    in
    concatStringsSep "/" (
      foldl' (
        acc: component:
        if component == "" || component == "." then
          acc
        else if component == ".." then
          init acc
        else
          acc ++ [ component ]
      ) (init fromParts) relParts
    );

  downloadPath =
    { path, checksum }:
    downloadRemoteModule {
      url = "https://jsr.io/@${scope}/${name}/${version}${path}";
      sha256 = removePrefix "sha256-" checksum;

      passthru = {
        moduleSiblings = builtins.foldl' (
          acc: dep:
          if !(hasPrefix "." dep.specifier) then
            acc
          else
            let
              depPath = traversePath path dep.specifier;
            in
            acc
            ++ (singleton (downloadPath {
              path = depPath;
              checksum = meta.manifest.${depPath}.checksum;
            }))
        ) [ ] ((meta.moduleGraph2 or meta.moduleGraph1).${path}.dependencies or [ ]);
      };
    };
in
{
  files = mapAttrs (
    path: info:
    downloadPath {
      inherit path;
      checksum = info.checksum;
    }
  ) meta.manifest;
  exports = meta.exports;
  meta = metaFile;
}
