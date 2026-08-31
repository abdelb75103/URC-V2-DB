import "server-only";
import { readFile } from "node:fs/promises";
import path from "node:path";

const publicRoot = path.resolve(process.cwd(), "public");
let sharedAssetsPromise: Promise<{
  heroDataUri: string;
  urcLogoDataUri: string;
  partnerLogoDataUri: string;
}> | null = null;

function mimeType(assetPath: string): string {
  if (assetPath.endsWith(".svg")) return "image/svg+xml";
  if (assetPath.endsWith(".webp")) return "image/webp";
  if (/\.jpe?g$/i.test(assetPath)) return "image/jpeg";
  return "image/png";
}

async function publicAssetDataUri(assetPath: string): Promise<string> {
  const resolvedPath = path.resolve(publicRoot, assetPath.replace(/^\/+/, ""));
  if (!resolvedPath.startsWith(`${publicRoot}${path.sep}`)) throw new Error("Report asset is outside the public asset directory");
  const bytes = await readFile(resolvedPath);
  return `data:${mimeType(resolvedPath)};base64,${bytes.toString("base64")}`;
}

function sharedAssets() {
  sharedAssetsPromise ??= Promise.all([
    publicAssetDataUri("images/report/urc-injury-surveillance-hero.jpg"),
    publicAssetDataUri("images/URC.png"),
    publicAssetDataUri("images/UCDLogo.png"),
  ]).then(([heroDataUri, urcLogoDataUri, partnerLogoDataUri]) => ({ heroDataUri, urcLogoDataUri, partnerLogoDataUri }));
  return sharedAssetsPromise;
}

export async function loadReportBrand(crestPath: string, accentColour: string): Promise<{
  crestDataUri: string;
  accentColour: string;
  heroDataUri: string;
  urcLogoDataUri: string;
  partnerLogoDataUri: string;
}> {
  const [crestDataUri, shared] = await Promise.all([publicAssetDataUri(crestPath), sharedAssets()]);
  return { crestDataUri, accentColour, ...shared };
}
