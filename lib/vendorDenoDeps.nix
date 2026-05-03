{
  lib,
  runCommandLocal,
  writeText,
  buildModuleGraph,
  downloadRemoteModule,
  downloadModuleFromSpecifier,
}:

let
  inherit (lib)
    concatStrings
    concatStringsSep
    foldl'
    hasPrefix
    hasSuffix
    importJSON
    init
    mapAttrs
    mapAttrsToList
    nameValuePair
    optionalString
    recursiveUpdate
    removePrefix
    removeSuffix
    splitString
    zipListsWith
    ;

in
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
  denoLockParsed = args.denoLockParsed or (importJSON (args.denoLock or (src + "/deno.lock")));

  splitUri =
    uri:
    let
      match = builtins.match "^([A-Za-z][+-.A-Za-z]*:)//([^/]*)?(/[^?]*)?([?].*)?$" uri;
    in
    if match == null then
      null
    else
      builtins.listToAttrs (
        zipListsWith nameValuePair [
          "scheme"
          "authority"
          "path"
          "query"
        ] match
      );

  isRemote = uri: uri ? scheme && (uri.scheme == "http:" || uri.scheme == "https:");

  moduleGraph =
    args.denoModuleGraph or (buildModuleGraph {
      inherit denoConfig denoLockParsed;
      rootModules = map (
        entrypoint: if isRemote (splitUri entrypoint) then entrypoint else "${src}/${entrypoint}"
      ) entrypoints;
    });

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
        if hasSuffix ".json" uri.path && uri.query == "?module" then
          "${removeSuffix ".json" uri.path}.js"
        else
          uri.path;
    in
    sanitizePath "./${uri.authority}${path}";

  pathIsDir = hasSuffix "/";

  pathHasExtension =
    path:
    builtins.any (ext: hasSuffix ext path) [
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
    path + (optionalString (!(pathIsDir uri.path) && !(pathHasExtension uri.path)) (args.ext or ".js"));

  mappings =
    foldl'
      (
        acc: module:
        let
          uri = splitUri module.specifier;
        in
        if !(isRemote uri) then
          acc
        else if module.kind == "asserted" || module.kind == "esm" then
          recursiveUpdate acc {
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
in
runCommandLocal "build-vendor-dir" { } ''
  ${concatStrings (
    map
      (
        { module, path }:
        # TODO: investigate a better way to avoid overlapping modules
        ''
          mkdir -p "$out/${dirOf path}"
          cp "${module}" "$out/${path}"
          chmod +w "$out/${path}"
        ''
      )
      (
        (mapAttrsToList (specifier: path: {
          module = downloadModuleFromSpecifier { inherit specifier denoLockParsed; };
          inherit path;
        }) mappings.mappings)
        ++ (mapAttrsToList (name: module: {
          module = downloadRemoteModule {
            url = module.url or name;
            hash = module.hash or module;
          };
          path = mkVendorPath (splitUri (module.url or name));
        }) extraImports)
      )
  )}

  cat > $out/import_map.json << 'EOF'
  ${builtins.toJSON (
    recursiveUpdate
      (foldl'
        (
          acc: referrer:
          let
            referrerUri = splitUri referrer.specifier;
            scope = mkVendorFilePath { uri = (referrerUri // { path = "/"; }); };
          in
          if referrer.kind == "asserted" then
            recursiveUpdate acc {
              scopes."${scope}"."${referrerUri.path}" = mappings.mappings.${referrer.specifier};
            }
          else if referrer.kind == "esm" then
            foldl' (
              acc: dep:
              let
                depUri = splitUri dep.specifier;
                resolvedSpecifier = resolveRedirect dep.code.specifier;
                resolvedUri = splitUri resolvedSpecifier;
                mapping = {
                  ${dep.specifier} = mappings.mappings.${resolvedSpecifier};
                };
              in
              # Import had an error
              if dep.code or { } ? error then
                # Import is a dynamic import from a CommonJS file, which failed
                # to resolve. This is likely an unprefixed npm package or part
                # of the node standard library
                if dep.isDynamic or false && dep.code.resolutionMode or "" == "require" then
                  acc
                else
                  let
                    inherit (dep.code.span) start;
                    location = "${toString start.line}:${toString start.character}";
                  in
                  throw ''
                    Unable to resolve "${dep.specifier}": ${dep.code.error}

                    ${if dep.isDynamic then "Dynamically i" else "I"}mported at ${referrer.specifier}:${location}
                  ''
              # Import is a normal URL
              else if isRemote depUri then
                if
                  resolvedUri.path
                  != (removePrefix "./${resolvedUri.authority}" mappings.mappings.${dep.code.specifier})
                then
                  # Import was saved in a different location either because it
                  # contained forbidden characters or was missing a file extension,
                  # so it should be included
                  recursiveUpdate acc { imports = mapping; }
                else if depUri.authority != resolvedUri.authority then
                  # Import is a redirect so it should be included
                  recursiveUpdate acc { imports = mapping; }
                # Import should be covered by the base specifier blanked imports
                else
                  acc
              # Import is identity so it's probably a built in module
              else if dep.specifier == resolvedSpecifier then
                acc
              else if
                ((hasPrefix "./" dep.specifier) || (hasPrefix "../" dep.specifier))
                && ((traversePath referrer.specifier dep.specifier) == dep.code.specifier)
              then
                # Import is a simple relative import and doesn't need special handling
                acc
              else if isRemote referrerUri then
                # Import is an absolute import from a remote referrer so it should be
                # included, but scoped under its base specifier
                recursiveUpdate acc { scopes."${scope}" = mapping; }
              # Import mapping was present in the original import map so it should be
              # included
              else
                recursiveUpdate acc { imports = mapping; }
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
          (mapAttrs (base: _: mkVendorPath (splitUri base)) mappings.baseSpecifiers)
          // (mapAttrs (name: module: mkVendorPath (splitUri (module.url or name))) extraImports);
      }
  )}
  EOF
''
