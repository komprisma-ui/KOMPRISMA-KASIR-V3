const base = process.env.KASIRA_DEPLOYED_URL;
if (!base) throw new Error("KASIRA_DEPLOYED_URL is required.");

const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
let pageResponse;
for (let attempt = 0; attempt < 8; attempt++) {
  try {
    pageResponse = await fetch(base, { cache: "no-store" });
    if (pageResponse.ok) break;
  } catch { /* GitHub Pages CDN can take a moment to publish. */ }
  await wait(2000);
}
if (!pageResponse?.ok) throw new Error("Published KASIRA page is unavailable: HTTP " + (pageResponse?.status || "network error"));

const html = await pageResponse.text();
if (!html.includes('<div id="root"></div>')) throw new Error("Published HTML is missing the React root.");
const refs = [...html.matchAll(/(?:src|href)="([^"]+\.(?:m?js|css)(?:\?[^"]*)?)"/gi)].map(x => x[1]);
const jsRefs = refs.filter(x => /\.(?:m?js)(?:\?[^"]*)?$/i.test(x));
const cssRefs = refs.filter(x => /\.css(?:\?[^"]*)?$/i.test(x));
if (!jsRefs.length) throw new Error("No JavaScript application bundle was published.");
if (!cssRefs.length) throw new Error("No CSS bundle was published.");

const loadAsset = async ref => {
  const url = new URL(ref, base);
  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok) throw new Error("Published asset returned HTTP " + response.status + ": " + url.href);
  return { url: url.href, body: await response.text() };
};
const js = (await Promise.all(jsRefs.map(loadAsset))).map(x => x.body).join("\n");
await Promise.all(cssRefs.map(loadAsset));
for (const marker of ["Masuk ke KASIRA", "user1234", "kasira_create_invitation", "kasira_accept_invitation", "ACCOUNT RECOVERY", "Menyiapkan ruang usaha"]) {
  if (!js.includes(marker)) throw new Error("Published application bundle is missing expected release marker: " + marker);
}
console.log("KASIRA published-site smoke check passed. Login/demo UI, invitation RPCs, JS and CSS assets are present and reachable.");
