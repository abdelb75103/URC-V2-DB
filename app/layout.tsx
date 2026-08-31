import type { Metadata } from 'next';
import './globals.css';
import { SiteHeader } from '@/components/site-header';

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
      <body className="min-h-screen font-body antialiased flex flex-col">
        <SiteHeader />
        <main className="flex-1 w-full">{children}</main>
        <footer className="p-4 text-center text-xs text-muted-foreground">
          {`© ${new Date().getFullYear()} United Rugby Championship & University College Dublin. All rights reserved.`}
        </footer>
      </body>
    </html>
  );
}
