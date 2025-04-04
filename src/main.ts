import { parseArgs } from "$std/cli/parse_args.ts";
import { dirname } from "$std/path/posix/dirname.ts";
import { isAbsolute } from "$std/path/posix/is_absolute.ts";
import { join } from "$std/path/posix/join.ts";
import { toFileUrl } from "$std/path/posix/to_file_url.ts";

import { createGraph, init } from "deno_graph/mod.ts";
import { parseFromString as parseImportMap } from "import-maps/parser.js";
import { resolve as resolveImport } from "import-maps/resolver.js";

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
  let importMap: ImportMap = { imports: {}, scopes: {} };
  let defaultJsxImportSource: string | undefined;
  let virtualRemotes: Record<string, string> = {};
  try {
    const configPath = flags.config
      ? toAbsolutePath(flags.config)
      : join(Deno.cwd(), "deno.json");
    const rootDir = dirname(configPath);

    let rawImportMap: string;
    const config = JSON.parse(await Deno.readTextFile(configPath));
    if (flags["import-map"]) {
      rawImportMap = await Deno.readTextFile(
        toAbsolutePath(flags["import-map"]),
      );
    } else if (config.importMap && !config.imports && !config.scopes) {
      const importMapPath = toAbsolutePath(config.importMap, rootDir);
      rawImportMap = await Deno.readTextFile(importMapPath);
    } else {
      if (config.importMap) {
        console.warn(
          "warning: importMap is ignored when imports or scopes is specified in the config file",
        );
      }

      // the stringify and then parse step is pretty clunky but the import maps
      // reference implementation doesn't export its normalize methods, so
      // unless I want to reimplement them I kind of have to do this
      rawImportMap = JSON.stringify({
        imports: config.imports,
        scopes: config.scopes,
      });
    }

    importMap = parseImportMap(rawImportMap, toFileUrl(rootDir));
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

  // https://github.com/denoland/deno/issues/2552
  const wasmUrl = import.meta.resolve("deno_graph/deno_graph_wasm_bg.wasm");
  await init({ url: new URL(wasmUrl) });

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
          return virtual == null ? undefined : {
            kind: "module",
            specifier,
            content: await Deno.readTextFile(virtual),
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
        const scriptUrl = new URL(referrer);
        return resolveImport(specifier, importMap, scriptUrl).toString();
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
