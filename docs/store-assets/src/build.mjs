// Dhruva AI store marketing frames (same system as ParkIn OS / Splitsly):
// numbered kicker, Fraunces headline with one gold phrase, the real app
// screen in a phone frame bleeding off the bottom.
//   node build.mjs            -> ../google-play/*, ../app-store/*
// Inputs: ../work/raw_ios (simulator captures, scripts/capture-store-shots.sh)
//         ../work/raw_android (prep_android.py output)
// Needs playwright: PLAYWRIGHT_FROM=<dir with node_modules/playwright>.
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(
  path.join(process.env.PLAYWRIGHT_FROM ?? process.cwd(), "package.json"),
);
const { chromium } = require("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const htmlDir = path.join(root, "work/html");
fs.mkdirSync(htmlDir, { recursive: true });

// design-tokens.json color.dark
const C = { bg: "#0E1220", surface: "#1F263D", gold: "#EBBA47", sky: "#8FB0DE", text: "#EDEFF8" };

// *word* = gold emphasis. Short, specific, no em dashes.
const FRAMES = [
  { id: "01-understand", shot: "03_workflow_reply", back: "02_workflows",
    k: "Workflows", h: "Understand any bill, *privately*" },
  { id: "02-offline", shot: "04_chat", k: "Offline AI", h: "AI that runs *on your phone*" },
  { id: "03-one-tap", shot: "02_workflows", k: "One tap", h: "*12 workflows*, one tap each" },
  { id: "04-models", shot: "05_models", k: "Models", h: "Pick a model that *fits your phone*" },
];

const TARGETS = {
  play: { W: 1080, H: 1920, plat: "android", out: "google-play/phone" },
  apple: { W: 1206, H: 2622, plat: "ios", out: "app-store/iphone-6.3" },
};

const PLAT = {
  android: { lw: 412, lh: 915, bez: 9, rad: 44 },
  ios: { lw: 440, lh: 956, bez: 11, rad: 58 },
};

// Android captures have the status area painted out, so draw one; iOS
// captures already carry the real status bar + Dynamic Island.
function androidChrome(k) {
  const col = C.text;
  const s = 13 * k;
  return `<div style="position:absolute;left:0;right:0;top:${9 * k}px;display:flex;justify-content:space-between;align-items:center;padding:0 ${22 * k}px;height:${18 * k}px;font:700 ${14.5 * k}px/1 Manrope;color:${col}">
      <span>9:41</span>
      <span style="display:flex;gap:${5 * k}px;align-items:center">
        <svg width="${s * 1.2}" height="${s}" viewBox="0 0 19 15"><g fill="none" stroke="${col}" stroke-width="2.2" stroke-linecap="round"><path d="M1.5 5.2a11 11 0 0 1 16 0"/><path d="M4.6 8.6a6.6 6.6 0 0 1 9.8 0"/></g><circle cx="9.5" cy="12.4" r="1.9" fill="${col}"/></svg>
        <svg width="${s}" height="${s}" viewBox="0 0 16 16"><path d="M15.2 1.5v13.3H1.9z" fill="${col}"/></svg>
        <svg width="${s * 1.1}" height="${s * 1.1}" viewBox="0 0 16 16"><rect x="1" y="3.6" width="14" height="8.8" rx="2.6" fill="${col}" fill-opacity=".35"/><rect x="1" y="3.6" width="10.5" height="8.8" rx="2.6" fill="${col}"/></svg>
      </span></div>
    <div style="position:absolute;left:50%;top:${11 * k}px;width:${12 * k}px;height:${12 * k}px;margin-left:${-6 * k}px;border-radius:50%;background:#050607"></div>
    <div style="position:absolute;left:50%;bottom:${6 * k}px;width:${110 * k}px;height:${4 * k}px;margin-left:${-55 * k}px;border-radius:${3 * k}px;background:${C.text};opacity:.6"></div>`;
}

function phone(plat, img, h, extra = "") {
  const P = PLAT[plat];
  const k = h / (P.lh + P.bez * 2);
  const w = (P.lw + P.bez * 2) * k;
  return `<div class="phone" style="width:${w}px;height:${h}px;border-radius:${(P.rad + P.bez) * k}px;padding:${P.bez * k}px;${extra}">
    <div class="side" style="right:${-3 * k}px;top:${190 * k}px;width:${4 * k}px;height:${86 * k}px"></div>
    <div class="side" style="left:${-3 * k}px;top:${150 * k}px;width:${4 * k}px;height:${50 * k}px"></div>
    <div style="position:relative;width:100%;height:100%;border-radius:${P.rad * k}px;overflow:hidden;background:${C.bg}">
      <img src="${img}" style="display:block;width:100%;height:100%;object-fit:cover;object-position:top">
      ${plat === "android" ? androidChrome(k) : ""}
    </div></div>`;
}

const baseCss = (W, H) => `
@font-face{font-family:Fraunces;src:url(${root}/src/fonts/Fraunces-Variable.ttf)}
@font-face{font-family:Manrope;src:url(${root}/src/fonts/Manrope-Variable.ttf)}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:${W}px;height:${H}px;overflow:hidden}
body{background:${C.bg};font-family:Manrope,sans-serif;position:relative}
.phone{position:absolute;background:#06080e;box-shadow:0 0 0 ${W * 0.0016}px #2D385C, 0 ${W * 0.03}px ${W * 0.07}px rgba(0,0,0,.6)}
.side{position:absolute;background:#2D385C;border-radius:2px}
em{font-style:normal;color:${C.gold}}
`;

function frameHtml(t, f) {
  const { W, H, plat } = t;
  const raw = `${root}/work/raw_${plat}/`;
  const tall = H / W > 1.9;
  const top = H * (tall ? 0.205 : 0.235);
  const bleed = H * 0.022;
  const P = PLAT[plat];
  const r = (P.lw + P.bez * 2) / (P.lh + P.bez * 2);
  let phones;
  if (f.back) {
    // Anchor under the headline and let both phones run off the bottom, so a
    // tall (App Store) canvas has no dead band between caption and device.
    const fh = Math.max(H - top + bleed, (W * 0.74) / r);
    const fw = Math.min(r * fh, W * 0.8), fhh = fw / r, gh = fhh * 0.9;
    phones =
      phone(plat, raw + f.back + ".png", gh, `left:${W * 0.035}px;top:${top + H * 0.05}px;filter:brightness(.6)`) +
      phone(plat, raw + f.shot + ".png", fhh, `left:${W - fw - W * 0.035}px;top:${top}px`);
  } else {
    const mh = H - top + bleed;
    phones = phone(plat, raw + f.shot + ".png", mh, `left:${(W - r * mh) / 2}px;top:${top}px`);
  }
  const dashes = [0, 1, 2, 3].map(() => `<i style="display:block;width:${W * 0.03}px;height:${W * 0.0075}px;border-radius:${W}px;background:${C.gold}"></i>`).join("");
  return `<!doctype html><meta charset="utf-8"><style>${baseCss(W, H)}
.cap{position:absolute;left:${W * 0.075}px;right:${W * 0.075}px;top:${H * 0.05}px}
.k{display:flex;align-items:center;gap:${W * 0.022}px;font:800 ${W * 0.026}px/1 Manrope;letter-spacing:${W * 0.0035}px;text-transform:uppercase;color:${C.gold}}
.k span.n{color:rgba(237,239,248,.45)}
.k .d{display:flex;gap:${W * 0.008}px}
h1{margin-top:${H * 0.018}px;font:600 ${W * 0.088}px/1.04 Fraunces;color:${C.text};letter-spacing:${-W * 0.0016}px;max-width:${W * 0.86}px;text-wrap:balance}
.glow{position:absolute;left:50%;top:${top - W * 0.1}px;width:${W * 1.2}px;height:${W * 1.2}px;margin-left:${-W * 0.6}px;background:radial-gradient(closest-side,rgba(235,186,71,.13),rgba(235,186,71,0))}
</style><body><div class="glow"></div>
<div class="cap"><div class="k"><span class="n">${f.id.slice(0, 2)}</span><span class="d">${dashes}</span><span>${f.k}</span></div>
<h1>${f.h.replace(/\*(.+?)\*/g, "<em>$1</em>")}</h1></div>${phones}</body>`;
}

function featureHtml() {
  const W = 1024, H = 500;
  const raw = `${root}/work/raw_android/`;
  return `<!doctype html><meta charset="utf-8"><style>${baseCss(W, H)}
.logo{position:absolute;left:64px;top:52px;display:flex;align-items:center;gap:16px}
.logo img{width:64px;height:64px;border-radius:16px}
.logo b{font:600 34px/1 Fraunces;color:${C.text}}
h1{position:absolute;left:64px;top:160px;font:600 50px/1.05 Fraunces;color:${C.text};letter-spacing:-.5px}
p{position:absolute;left:64px;top:300px;width:420px;font:600 21px/1.4 Manrope;color:rgba(237,239,248,.7)}
.dash{position:absolute;left:64px;bottom:58px;display:flex;gap:7px}.dash i{display:block;width:30px;height:7px;border-radius:7px;background:${C.gold}}
.glow{position:absolute;right:-80px;top:-80px;width:760px;height:760px;background:radial-gradient(closest-side,rgba(235,186,71,.14),rgba(235,186,71,0))}
</style><body><div class="glow"></div>
<div class="logo"><img src="${root}/src/icon.png"><b>Dhruva AI</b></div>
<h1>Private AI that<br>runs <em>on your phone</em></h1>
<p>Summarize, translate and chat offline. No cloud, no account.</p>
<div class="dash"><i></i><i></i><i></i><i></i></div>
${phone("android", raw + "02_workflows.png", 500, `left:540px;top:${H - 370}px;filter:brightness(.6)`)}
${phone("android", raw + "03_workflow_reply.png", 600, `left:${W - 600 * 0.452 - 56}px;top:${H - 460}px`)}
</body>`;
}

const browser = await chromium.launch();
async function shot(html, name, W, H, outPath) {
  const f = path.join(htmlDir, name + ".html");
  fs.writeFileSync(f, html);
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  await page.goto("file://" + f);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(250);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  await page.screenshot({ path: outPath, clip: { x: 0, y: 0, width: W, height: H } });
  await page.close();
}
for (const [name, t] of Object.entries(TARGETS)) {
  for (const f of FRAMES) {
    await shot(frameHtml(t, f), `${name}-${f.id}`, t.W, t.H, path.join(root, t.out, `${f.id}.png`));
  }
}
await shot(featureHtml(), "feature", 1024, 500, path.join(root, "google-play", "feature-graphic.png"));
await browser.close();
console.log("ok");
