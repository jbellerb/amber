{
  lib,
  runtimeShell,
  mkDenoDerivation,
  deno,
}:

let
  inherit (lib)
    makeBinPath
    optional
    optionalString
    versionAtLeast
    ;

in
{
  pname,
  src,
  entrypoint ? "main.ts",
  denoCacheDir ? null,
  ...
}@args:
mkDenoDerivation (
  args
  // {
    pname = "${pname}-wrapper";

    outputs = [ "out" ] ++ (optional (!(args ? denoCacheDir)) "cache");
    denoCacheDir = args.denoCacheDir or "$cache";

    # Empty eval is needed because sometimes deno cache doesn't initialize the
    # cache databases for node modules, which need to exist for the script to
    # start even if node modules aren't used.
    buildPhaseCommand = optionalString (!(args ? denoCacheDir)) ''
      deno install --config "$denoConfigVendored" --entrypoint "${entrypoint}"
      deno eval --config "$denoConfigVendored" ""
    '';

    installPhaseCommand = ''
      mkdir -p $out/bin
      cat > $out/bin/${pname} << EOF
      #!${runtimeShell}

      export PATH="${makeBinPath [ deno ]}:\$PATH"
      export DENO_DIR="$DENO_DIR"

      deno run -A --cached-only --config "$denoConfigVendored" ${src}/${entrypoint} "\$@"
      EOF

      chmod +x $out/bin/${pname}
    '';
  }
)
