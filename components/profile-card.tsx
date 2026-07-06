import Image from 'next/image';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { cn } from '@/lib/utils';

interface ProfileCardProps {
  name: string;
  title: string;
  subtitle?: string;
  imageUrl: string;
  imageHint: string;
  bio: string[];
  reverse?: boolean;
  imagePosition?: string;
}

export function ProfileCard({
  name,
  title,
  subtitle,
  imageUrl,
  imageHint,
  bio,
  reverse = false,
  imagePosition = 'object-center',
}: ProfileCardProps) {
  return (
    <Card className="overflow-hidden">
      <div className={cn('grid items-start md:grid-cols-3', reverse && 'md:grid-flow-col-dense')}>
        <div className={cn('relative h-80 w-full md:h-full', reverse && 'md:col-start-3')}>
          <Image
            src={imageUrl}
            alt={`Profile picture of ${name}`}
            fill
            sizes="(max-width: 768px) 100vw, 33vw"
            className={cn('object-cover', imagePosition)}
            data-ai-hint={imageHint}
          />
        </div>
        <div className="md:col-span-2">
          <CardHeader>
            <CardTitle className="text-3xl">{name}</CardTitle>
            <div>
              <p className="font-semibold text-primary">{title}</p>
              {subtitle && <p className="text-primary">{subtitle}</p>}
            </div>
          </CardHeader>
          <CardContent className="space-y-4 text-muted-foreground">
            {bio.map((paragraph, index) => (
              <p key={index}>{paragraph}</p>
            ))}
          </CardContent>
        </div>
      </div>
    </Card>
  );
}
