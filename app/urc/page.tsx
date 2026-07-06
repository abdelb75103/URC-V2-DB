import { LockedShell } from '@/components/locked-shell';
import { StaticImages } from '@/lib/placeholder-images';

export const dynamic = 'force-static';

export default function UrcOverallPage() {
  return (
    <LockedShell
      title="URC Overall"
      subtitle="League-wide injury & exposure aggregate"
      crest={StaticImages.urcLogo}
      reason="The league-wide aggregate combines cleared team datasets. It unlocks once enough teams have passed the V2 workflow and a governance-approved league aggregate with disclosure control is released. Munster is the pilot dataset."
    />
  );
}
