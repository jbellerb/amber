{ lib, newScope }:

lib.makeScope newScope (
  self:
  let
    inherit (self) callPackage;
  in
  {
    buildDenoScript = callPackage ./buildDenoScript.nix { };
    buildModuleGraph = callPackage ./buildModuleGraph.nix { };
    downloadRemoteModule = callPackage ./downloadRemoteModule.nix { };
    downloadJSRPackage = callPackage ./downloadJSRPackage.nix { };
    downloadModuleFromSpecifier = callPackage ./downloadModuleFromSpecifier.nix { };
    mkDenoDerivation = callPackage ./mkDenoDerivation.nix { };
    vendorDenoDeps = callPackage ./vendorDenoDeps.nix { };

    graphAnalyzer = callPackage ../src/default.nix { };

    buildFreshSite = callPackage ./buildFreshSite.nix { };
    denoCheck = callPackage ./denoCheck.nix { };
    denoFmt = callPackage ./denoFmt.nix { };
    denoLint = callPackage ./denoLint.nix { };
  }
)
