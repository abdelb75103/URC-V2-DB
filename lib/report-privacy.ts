import "server-only";
import { teams } from "@/config/teams";

export function reportProtectedTerms(subjectTeamId?: string): string[] {
  const protectedAliases = Array.from({ length: 26 }, (_, index) => `Team ${String.fromCharCode(65 + index)}`);
  const protectedTeams = teams.filter((team) => team.id !== subjectTeamId);
  return [...new Set([...protectedTeams.flatMap((team) => [team.id, team.name]), ...protectedAliases])];
}
