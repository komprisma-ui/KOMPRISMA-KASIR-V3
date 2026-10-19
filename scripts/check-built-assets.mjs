import fs from "node:fs";
import path from "node:path";

const dist = path.resolve("dist");
const htmlFile = path.join(dist, "index.html");
if (!fs.existsSync(htmlFile)) throw new Error("Build output is missing dist/index.html.");

const html = fs.readFileSync(htmlFile, "utf8");
if (!html.includes('<div id="root"></div>')) throw new Error("React root element is missing from built index.html.");

const base = String(process.env.VITE_BASE_PATH || "/").replace(/^\/+|\/+$/g, "");
const refs = [...html.matchAll(/(?:src|href)="([^"]+\.(?:m?js|css)(?:\?[^"]*)?)"/gi)].map(match => match[1]);
const assets = refs.filter(ref => /\.(?:m?js|css)(?:\?[^"]*)?$/i.test(ref));
if (!assets.some(ref => /\.(?:m?js)(?:\?[^"]*)?$/i.test(ref))) {
  throw new Error("Built page does not reference a JavaScript entry bundle; login UI cannot mount.");
}

for (const ref of assets) {
  const pathname = decodeURIComponent(ref.split("?")[0]);
  let relative = pathname.replace(/^\/+/, "");
  if (base && relative.startsWith(base + "/")) relative = relative.slice(base.length + 1);
  const filename = path.resolve(dist, relative);
  if (!filename.startsWith(dist + path.sep)) throw new Error("Unsafe build asset path: " + ref);
  if (!fs.existsSync(filename)) throw new Error("Broken asset reference in built index.html: " + ref);
  if (fs.statSync(filename).size === 0) throw new Error("Empty build asset: " + ref);
}

if (/src\/main\.jsx/.test(html)) throw new Error("Source entrypoint leaked into production HTML instead of a compiled bundle.");
console.log(`KASIRA build asset checks passed (${assets.length} JS/CSS assets, base=${base || "/"}).`);
