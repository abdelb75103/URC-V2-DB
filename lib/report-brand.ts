import "server-only";
import { readFile } from "node:fs/promises";
import path from "node:path";

export async function loadReportBrand(crestPath: string, accentColour: string): Promise<{
  crestDataUri: string;
  accentColour: string;
}> {
  const publicRoot = path.resolve(process.cwd(), "public");
  const assetPath = path.resolve(publicRoot, crestPath.replace(/^\/+/, ""));
  if (!assetPath.startsWith(`${publicRoot}${path.sep}`)) throw new Error("Report crest is outside the public asset directory");
  const bytes = await readFile(assetPath);
  const mime = assetPath.endsWith(".svg") ? "image/svg+xml" : assetPath.endsWith(".webp") ? "image/webp" : "image/png";
  return { crestDataUri: `data:${mime};base64,${bytes.toString("base64")}`, accentColour };
}
