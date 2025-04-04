{
  lib,
  runCommandLocal,
  writeText,
  downloadModuleFromSpecifier,
  downloadRemoteModule,
  graphAnalyzer,
}:

{
  rootModules,
  denoConfig ? null,
  denoConfigParsed ? null,
  denoLock ? null,
  denoLockParsed ? null,
}@args:
let
  denoConfig =
    args.denoConfig or (writeText "deno-config" (
      builtins.toJSON (args.denoConfigParsed or (throw "Missing attribute: denoConfig"))
    ));
  denoLockParsed =
    args.denoLockParsed or (lib.importJSON (args.denoLock or (throw "Missing attribute: denoLock")));

  genModuleGraph =
    {
      specifiers,
      virtualRemotes ? null,
    }:
    builtins.fromJSON (
      builtins.unsafeDiscardStringContext (
        builtins.readFile (
          runCommandLocal "build-module-graph" { } ''
            ${
              lib.optionalString (virtualRemotes != null) ''
                cat > "$TMPDIR/virtual_remotes.json" << 'EOF'
                ${builtins.toJSON virtualRemotes}
                EOF
              ''
            }${graphAnalyzer}/bin/graph-analyzer --config "${denoConfig}" ${
              lib.optionalString (virtualRemotes != null) "--virtual-remotes \"$TMPDIR/virtual_remotes.json\" "
            }${lib.concatStringsSep " " (builtins.map lib.escapeShellArg specifiers)} > $out
          ''
        )
      )
    );

  resolveJSRSiblings =
    {
      module,
      known ? { },
    }:
    builtins.foldl'
      (
        acc: sibling:
        if builtins.hasAttr sibling.url acc.known then
          acc
        else
          let
            resolved = resolveJSRSiblings {
              module = sibling;
              inherit known;
            };
          in
          acc
          // {
            known = acc.known // resolved.known;
            remotes = acc.remotes ++ [ (lib.nameValuePair (sibling.url) "${sibling}") ] ++ resolved.remotes;
          }
      )
      {
        known = known // {
          ${module.url} = null;
        };
        remotes = [ ];
      }
      module.moduleSiblings;

  serializeVirtualModule =
    module: specifier:
    (
      if module ? redirection then
        (lib.nameValuePair specifier {
          file = "${module}";
          redirect = module.redirection;
        })
      else
        (lib.nameValuePair (module.url or specifier) "${module}")
    );

  genModuleGraphRecursive =
    {
      rootModules,
      modules,
      packages,
      redirects,
    }:
    let
      graph = genModuleGraph {
        specifiers = builtins.map (module: module.specifier) rootModules;
        virtualRemotes = builtins.listToAttrs (
          builtins.concatMap (
            { module, specifier }:
            [ (serializeVirtualModule module specifier) ]
            ++ (lib.optionals (module ? moduleSiblings) (resolveJSRSiblings { inherit module; }).remotes)
            ++ (lib.optionals (module ? packageMeta) [
              # deno_graph prefers to do package resolution itself so I need to
              # provide it with the jsr.io metadata files. Version metadata is
              # fine, but the package metadata doesn't have an integrity check
              # in the lockfile so I don't have access to it. Fortunately, I
              # can just write a fake one.
              (lib.nameValuePair module.packageMeta.url module.packageMeta)
              (lib.nameValuePair
                "${lib.removeSuffix "/${module.packageMeta.packageVersion}_meta.json" module.packageMeta.url}/meta.json"
                (
                  writeText (module.packageMeta.packageScope + "-" + module.packageMeta.packageName + "-meta.json") (
                    builtins.toJSON {
                      scope = module.packageMeta.packageScope;
                      name = module.packageMeta.packageName;
                      versions = {
                        ${module.packageMeta.packageVersion} = { };
                      };
                    }
                  )
                )
              )
            ])
          ) rootModules
        );
      };
      partition = builtins.partition (module: module ? kind) (
        builtins.filter (
          module: !(builtins.hasAttr module.specifier modules) || !(modules.${module.specifier} ? kind)
        ) graph.modules
      );
      updated = {
        modules =
          modules
          // (builtins.listToAttrs (
            builtins.map (module: lib.nameValuePair module.specifier module) partition.right
          ));
        packages = packages // (graph.packages or { });
        redirects = redirects // graph.redirects;
      };
      nextLayer = genModuleGraphRecursive (
        updated
        // {
          rootModules = builtins.map (module: {
            module = downloadModuleFromSpecifier {
              inherit (module) specifier;
              inherit denoLockParsed;
            };
            inherit (module) specifier;
          }) partition.wrong;
        }
      );
    in
    {
      inherit (graph) roots;
    }
    // (
      if partition.wrong == [ ] then updated else { inherit (nextLayer) modules packages redirects; }
    );

  graph = genModuleGraphRecursive {
    rootModules = builtins.map (
      module:
      if lib.hasPrefix "http:" module || lib.hasPrefix "https:" module then
        {
          module = downloadRemoteModule {
            url = module;
            sha256 = denoLockParsed.remote.${module};
          };
          specifier = module;
        }
      else
        {
          inherit module;
          specifier = builtins.unsafeDiscardStringContext "file://${module}";
        }
    ) rootModules;
    modules = { };
    packages = { };
    redirects = { };
  };
in
{
  inherit (graph) roots packages redirects;
  modules = lib.attrValues graph.modules;
}
