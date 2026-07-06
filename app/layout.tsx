import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { cn } from '@/lib/utils';
import { SiteHeader } from '@/components/site-header';

const inter = Inter({ subsets: ['latin'], variable: '--font-sans' });

export const metadata: Metadata = {
  title: 'SCRIIPT — URC Injury Surveillance',
  description:
    'Surveillance of Continental Rugby Injury-Illness and Performance Tracking. A URC × UCD injury and exposure surveillance platform.',
  icons: {
    icon: '/images/URC.png',
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className="dark">
      <body
        className={cn(
          'min-h-screen font-body antialiased flex flex-col',
          inter.variable
        )}
      >
        <SiteHeader />
        <main className="flex-1 w-full">{children}</main>
        <footer className="p-4 text-center text-xs text-muted-foreground">
          {`© ${new Date().getFullYear()} United Rugby Championship & University College Dublin. All rights reserved.`}
        </footer>
      </body>
    </html>
  );
}
