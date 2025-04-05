{
  lib,
  runCommandLocal,
  writeText,
  buildModuleGraph,
  downloadRemoteModule,
  downloadModuleFromSpecifier,
}:

{
  src,
  entrypoints ? [ "main.ts" ],
  extraImports ? { },
  denoConfig ? null,
  denoConfigParsed ? null,
  denoLock ? null,
  denoLockParsed ? null,
  denoModuleGraph ? null,
}@args:
let
  denoConfig =
    args.denoConfig or (
      if denoConfigParsed != null then
        writeText "deno-config" (builtins.toJSON denoConfigParsed)
      else
        src + "/deno.json"
    );
  denoLockParsed = args.denoLockParsed or (lib.importJSON (args.denoLock or (src + "/deno.lock")));

  splitUri =
    uri:
    let
      match = builtins.match "^([A-Za-z][^:]*:)/{2}?([^/]*)?(/[^?]*)?([?].*)?$" uri;
    in
    if match == null then
      null
    else
      builtins.listToAttrs (
        lib.zipListsWith lib.nameValuePair [
          "scheme"
          "authority"
          "path"
          "query"
        ] match
      );

  isRemote = uri: uri ? scheme && (uri.scheme == "http:" || uri.scheme == "https:");

  moduleGraph =
    args.denoModuleGraph or (buildModuleGraph ({
      inherit denoConfig denoLockParsed;
      rootModules = builtins.map (
        entrypoint: if isRemote (splitUri entrypoint) then entrypoint else "${src}/${entrypoint}"
      ) entrypoints;
    }));

  sanitizePath = path: builtins.replaceStrings [ "*" ] [ "_" ] path;

  mkVendorPath =
    uri:
    let
      path =
        # Ugly hack to handle the convention esm.sh uses where .json files with
        # "?module" are wrapped into a real JS object. Since Deno does not give
        # us the MIME type (see the comment in mkVendorFilePath for more info),
        # but requires files to use the correct extension, I'm forced to rely on
        # simple heuristics like this...
        if lib.hasSuffix ".json" uri.path && uri.query == "?module" then
          "${lib.removeSuffix ".json" uri.path}.js"
        else
          uri.path;
    in
    sanitizePath "./${uri.authority}${path}";

  pathIsDir = lib.hasSuffix "/";

  pathHasExtension =
    path:
    builtins.any (ext: lib.hasSuffix ext path) [
      ".js"
      ".ts"
      ".mjs"
      ".mts"
      ".jsx"
      ".tsx"
      ".json"
    ];

  mkVendorFilePath =
    {
      uri,
      ext ? null,
    }@args:
    let
      path = mkVendorPath uri;
    in
    # As Deno lock files don't note the expected file type of remote modules,
    # (file types are present in jsr metadata) it is impossible to resolve
    # this if the import path doesn't end in one. I think this is an issue
    # with Deno. Until it's fixed, the best I can do is assume it's plain .js
    path
    + (lib.optionalString (!(pathIsDir uri.path) && !(pathHasExtension uri.path)) (args.ext or ".js"));

  mappings =
    lib.foldl'
      (
        acc: module:
        let
          uri = splitUri module.specifier;
        in
        if !(isRemote uri) then
          acc
        else if module.kind == "asserted" || module.kind == "esm" then
          lib.recursiveUpdate acc {
            mappings = {
              ${module.specifier} = mkVendorFilePath { inherit uri; };
            };
            baseSpecifiers = {
              "${uri.scheme}//${uri.authority}/" = null;
            };
          }
        else
          acc
      )
      {
        mappings = { };
        baseSpecifiers = { };
      }
      moduleGraph.modules;

  resolveRedirect =
    specifier:
    let
      resolveLimited =
        {
          specifier,
          seen,
          i,
        }:
        if builtins.hasAttr specifier seen then
          throw "Infinite loop of module redirects detected"
        else if i >= 10 then
          throw "Redirect chain exceeded the maximum allowed limit"
        else if builtins.hasAttr specifier moduleGraph.redirects then
          resolveLimited {
            specifier = moduleGraph.redirects.${specifier};
            seen = seen // {
              ${specifier} = null;
            };
            i = i + 1;
          }
        else
          specifier;
    in
    resolveLimited {
      inherit specifier;
      seen = { };
      i = 0;
    };

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
in
runCommandLocal "build-vendor-dir" { } ''
  ${lib.concatStrings (
    builtins.map
      (
        { module, path }:
        # TODO: investigate a better way to avoid overlapping modules
        ''
          mkdir -p "$out/${builtins.dirOf path}"
          cp "${module}" "$out/${path}"
          chmod +w "$out/${path}"
        ''
      )
      (
        (lib.mapAttrsToList (specifier: path: {
          module = downloadModuleFromSpecifier { inherit specifier denoLockParsed; };
          inherit path;
        }) mappings.mappings)
        ++ (lib.mapAttrsToList (name: module: {
          module = downloadRemoteModule {
            url = module.url or name;
            sha256 = module.sha256 or module;
          };
          path = mkVendorPath (splitUri (module.url or name));
        }) extraImports)
      )
  )}

  cat > $out/import_map.json << 'EOF'
  ${builtins.toJSON (
    lib.recursiveUpdate
      (lib.foldl'
        (
          acc: referrer:
          let
            referrerUri = splitUri referrer.specifier;
            scope = mkVendorFilePath { uri = (referrerUri // { path = "/"; }); };
          in
          if referrer.kind == "asserted" then
            lib.recursiveUpdate acc {
              scopes."${scope}"."${referrerUri.path}" = mappings.mappings.${referrer.specifier};
            }
          else if referrer.kind == "esm" then
            lib.foldl' (
              acc: dep:
              let
                depUri = splitUri dep.specifier;
                resolvedSpecifier = resolveRedirect dep.code.specifier;
                resolvedUri = splitUri resolvedSpecifier;
                mapping = {
                  ${dep.specifier} = mappings.mappings.${resolvedSpecifier};
                };
              in
              if isRemote depUri then
                if
                  resolvedUri.path
                  != (lib.removePrefix "./${resolvedUri.authority}" mappings.mappings.${dep.code.specifier})
                then
                  # Import was saved in a different location either because it
                  # contained forbidden characters or was missing a file extension,
                  # so it should be included
                  lib.recursiveUpdate acc { imports = mapping; }
                else if depUri.authority != resolvedUri.authority then
                  # Import is a redirect so it should be included
                  lib.recursiveUpdate acc { imports = mapping; }
                # Import should be covered by the base specifier blanked imports
                else
                  acc
              # Import is identity so it's probably a built in module
              else if dep.specifier == resolvedSpecifier then
                acc
              else if
                ((lib.hasPrefix "./" dep.specifier) || (lib.hasPrefix "../" dep.specifier))
                && ((traversePath referrer.specifier dep.specifier) == dep.code.specifier)
              then
                # Import is a simple relative import and doesn't need special handling
                acc
              else if isRemote referrerUri then
                # Import is an absolute import from a remote referrer so it should be
                # included, but scoped under its base specifier
                lib.recursiveUpdate acc { scopes."${scope}" = mapping; }
              # Import mapping was present in the original import map so it should be
              # included
              else
                lib.recursiveUpdate acc { imports = mapping; }
            ) acc (referrer.dependencies or [ ])
          else
            acc
        )
        {
          imports = { };
          scopes = { };
        }
        moduleGraph.modules
      )
      {
        # Add a mapping for each base specifier and extra import
        imports =
          (lib.mapAttrs (base: _: mkVendorPath (splitUri base)) mappings.baseSpecifiers)
          // (lib.mapAttrs (name: module: mkVendorPath (splitUri (module.url or name))) extraImports);
      }
  )}
  EOF
''
