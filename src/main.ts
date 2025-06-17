import { parseArgs } from "@std/cli/parse-args";
import { dirname } from "@std/path/posix/dirname";
import { isAbsolute } from "@std/path/posix/is-absolute";
import { join } from "@std/path/posix/join";
import { toFileUrl } from "@std/path/posix/to-file-url";

import { createGraph, init as initGraph } from "@deno/graph";
import {
  instantiate as initImport,
  parseFromJson as parseImportMap,
} from "import_map/import_map.generated.js";

type ImportMap = {
  imports: Record<string, string>;
  scopes: Record<string, Record<string, string>>;
};

function usage() {
  console.log("usage: ./main.ts [--config config] specifier ...");
}

function toAbsolutePath(path: string, base?: string) {
  return isAbsolute(path) ? path : join(base ?? Deno.cwd(), path);
}

const flags = parseArgs(Deno.args, {
  string: ["config", "import-map", "virtual-remotes"],
});
const args = flags._.filter((arg: unknown) =>
  typeof arg === "string"
) as string[];
if (args.length > 0) {
  // While Deno now supports WebAssembly imports, neither deno_graph nor
  // import_map have been updated to use a version of wasmbuild new enough
  // (>= 0.18.0) to generate them. Instead, both need to be instantiated
  // manually.
  const graphWasmUrl = import.meta.resolve(
    "@deno/graph/deno_graph_wasm_bg.wasm",
  );
  await initGraph({ url: new URL(graphWasmUrl) });
  const importWasmUrl = import.meta.resolve("import_map/import_map_bg.wasm");
  await initImport({ url: new URL(importWasmUrl) });

  const configPath = flags.config
    ? toAbsolutePath(flags.config)
    : join(Deno.cwd(), "deno.json");
  const rootDir = dirname(configPath);

  let rawImportMap = flags["import-map"]
    ? await Deno.readTextFile(toAbsolutePath(flags["import-map"]))
    : "{}";
  let doImportExpansion = false;
  let defaultJsxImportSource: string | undefined;
  let virtualRemotes: Record<
    string,
    string | { redirect: string; file: string }
  > = {};
  try {
    const config = JSON.parse(await Deno.readTextFile(configPath));

    if (rawImportMap == "{}") {
      if (config.importMap && !config.imports && !config.scopes) {
        const importMapPath = toAbsolutePath(config.importMap, rootDir);
        rawImportMap = await Deno.readTextFile(importMapPath);
      } else {
        if (config.importMap) {
          console.warn(
            "warning: importMap is ignored when imports or scopes is specified in the config file",
          );
        }
        rawImportMap = JSON.stringify({
          imports: config.imports,
          scopes: config.scopes,
        });
        // Match Deno's behavior of "expanding" shorthand imports, but only for
        // imports provided by deno.json.
        doImportExpansion = true;
      }
    }
    if (["react-jsx", "react-jsxdev"].includes(config.compilerOptions?.jsx)) {
      defaultJsxImportSource = config.compilerOptions?.jsxImportSource;
    }
    if (flags["virtual-remotes"]) {
      virtualRemotes = JSON.parse(
        await Deno.readTextFile(toAbsolutePath(flags["virtual-remotes"])),
      );
    }
  } catch (e) {
    if (!(e instanceof Deno.errors.NotFound)) throw e;
    console.warn(e);
  }

  const importMap = parseImportMap(
    toFileUrl(rootDir).toString(),
    rawImportMap,
    doImportExpansion,
  );

  const specifiers = args.map((specifier) => {
    try {
      return new URL(specifier);
    } catch {
      return toFileUrl(toAbsolutePath(specifier));
    }
  }).map((url) => url.toString());

  const graph = await createGraph(specifiers, {
    async load(specifier: string) {
      const url = new URL(specifier);
      switch (url.protocol) {
        case "file:": {
          const content = await Deno.readTextFile(url);
          return { kind: "module", specifier, content };
        }
        case "http:":
        case "https:":
        case "jsr:": {
          const virtual = virtualRemotes[specifier];
          if (virtual == null) return undefined;

          const { redirect = null, file } = typeof virtual === "string"
            ? { file: virtual }
            : virtual;
          return {
            kind: "module",
            specifier: redirect ?? specifier,
            content: await Deno.readTextFile(file),
          };
        }
        case "node:":
          return { kind: "external", specifier };
        default:
          return undefined;
      }
    },
    kind: "codeOnly",
    defaultJsxImportSource,
    resolve(specifier: string, referrer: string) {
      try {
        return importMap.resolve(specifier, referrer);
      } catch (e) {
        console.warn(e);
        return specifier;
      }
    },
  });

  console.log(JSON.stringify(graph));
} else {
  usage();
  Deno.exit(1);
}
