import "server-only";
import { teams } from "@/config/teams";

export function reportProtectedTerms(): string[] {
  const protectedAliases = Array.from({ length: 26 }, (_, index) => `Team ${String.fromCharCode(65 + index)}`);
  return [...new Set([...teams.flatMap((team) => [team.id, team.name]), ...protectedAliases])];
}
