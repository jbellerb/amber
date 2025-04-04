{ lib, fetchurl, downloadJSRPackage, downloadRemoteModule }:

{ specifier, integrity }:
  let
    parts = builtins.match "^jsr:/?(@[^@/]+)/([^@/]+)@([^@/]+)(/.+)?$" specifier;
    scope = builtins.elemAt parts 0;
    name = builtins.elemAt parts 1;
    version = builtins.elemAt parts 2;

    metaFile = fetchurl {
      name = lib.strings.sanitizeDerivationName specifier;
      url = "https://jsr.io/${scope}/${name}/${version}_meta.json";
      sha256 = integrity;

      passthru = {
        packageScope = scope;
        packageName = name;
        packageVersion = version;
      };
    };
    meta = lib.importJSON metaFile;

    traversePath = from: rel:
      let
        fromParts = lib.splitString "/" from;
        relParts = lib.splitString "/" rel;
      in lib.concatStringsSep "/" (lib.foldl' (acc: component:
        if component == "" || component == "." then acc
        else if component == ".." then lib.init acc
        else acc ++ [ component ]
      ) (lib.init fromParts) relParts);

    downloadPath = { path, checksum }: downloadRemoteModule {
      url = "https://jsr.io/${scope}/${name}/${version}${path}";
      sha256 = lib.removePrefix "sha256-" checksum;

      passthru = {
        moduleSiblings = builtins.foldl' (acc: dep:
          if !(lib.hasPrefix "." dep.specifier) then acc
          else
            let depPath = traversePath path dep.specifier;
            in acc ++ (lib.singleton (downloadPath {
              path = depPath;
              checksum = meta.manifest.${depPath}.checksum;
            }))
        ) [ ] (meta.moduleGraph1.${path}.dependencies or [ ]);
      };
    };

  in {
    files = lib.mapAttrs (path: info: downloadPath {
      inherit path;
      checksum = info.checksum;
    }) meta.manifest;
    exports = meta.exports;
    meta = metaFile;
  }
