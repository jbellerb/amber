{
  lib,
  stdenvNoCC,
  writeText,
  vendorDenoDeps,
  deno,
}:

{
  pname,
  version,
  src,
  entrypoints ? null,
  extraImports ? null,
  denoConfig ? null,
  denoConfigParsed ? null,
  denoLock ? null,
  denoLockParsed ? null,
  denoVendorDir ? null,
  denoConfigVendored ? null,
  denoCacheDir ? "$TMPDIR/deno",
  nativeBuildInputs ? null,
  configurePhase ? null,
  buildPhase ? null,
  buildPhaseCommand,
  installPhase ? null,
  installPhaseCommand,
  ...
}@args:
let
  denoConfigParsed =
    args.denoConfigParsed or (lib.importJSON (args.denoConfig or (src + "/deno.json")));
  denoLockParsed = args.denoLockParsed or (lib.importJSON (args.denoLock or (src + "/deno.lock")));
  denoVendorDir =
    args.denoVendorDir or (vendorDenoDeps (
      {
        inherit src denoConfigParsed denoLockParsed;
      }
      // (lib.optionalAttrs (entrypoints != null) { inherit entrypoints; })
      // (lib.optionalAttrs (extraImports != null) { inherit extraImports; })
      // (lib.optionalAttrs (denoConfig != null) { inherit denoConfig; })
    ));

  denoConfigVendored =
    args.denoConfigVendored or (writeText "deno-config-vendored" (
      builtins.toJSON (
        (builtins.removeAttrs denoConfigParsed [
          "imports"
          "scopes"
        ])
        // {
          importMap = "${denoVendorDir}/import_map.json";
        }
      )
    ));

  cleanArgs = builtins.removeAttrs args [
    "entrypoints"
    "extraImports"
    "denoConfig"
    "denoConfigParsed"
    "denoLock"
    "denoLockParsed"
    "denoVendorDir"
    "denoCacheDir"
    "buildPhaseCommand"
    "installPhaseCommand"
  ];
in
stdenvNoCC.mkDerivation (
  cleanArgs
  // {
    inherit pname version src;

    nativeBuildInputs = (args.nativeBuildInputs or [ ]) ++ [ deno ];
    denoConfigVendored = "${denoConfigVendored}";
    denoVendorDir = "${denoVendorDir}";

    configurePhase =
      args.configurePhase or ''
        runHook preConfigure

        export DENO_DIR="${denoCacheDir}"
        export DENO_MOD_NAME="${pname}"
        export DENO_MOD_VERSION="${version}"
        export DENO_VENDOR_DIR="${denoVendorDir}"

        runHook postConfigure
      '';

    buildPhase =
      args.buildPhase or ''
        runHook preBuild
        ${buildPhaseCommand}
        runHook postBuild
      '';

    installPhase =
      args.installPhase or ''
        runHook preBuild
        ${installPhaseCommand}
        runHook postBuild
      '';
  }
)
