import { notFound } from 'next/navigation';
import { getUnionById, unions } from '@/config/unions';
import { LockedShell } from '@/components/locked-shell';

export const dynamic = 'force-static';

export function generateStaticParams() {
  return unions.map((union) => ({ unionId: union.id }));
}

export default async function UnionPage({
  params,
}: {
  params: Promise<{ unionId: string }>;
}) {
  const { unionId } = await params;
  const union = getUnionById(unionId);
  if (!union) notFound();

  return (
    <LockedShell
      title={`${union.name} — ${union.governingBody}`}
      subtitle="Union-level injury & exposure aggregate"
      accent={union.accent}
      reason="Union-scoped dashboards unlock once a governance-approved league/union aggregate — with disclosure control applied across its member teams — has been released. No fabricated or legacy figures are shown."
    />
  );
}
