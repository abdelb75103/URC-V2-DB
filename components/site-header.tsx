'use client';

import * as React from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Menu } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useScroll } from '@/hooks/use-scroll';
import { Button } from '@/components/ui/button';
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet';
import { StaticImages } from '@/lib/placeholder-images';

const navLinks = [
  { href: '/', label: 'Home' },
  { href: '/project-details', label: 'Project Details' },
  { href: '/participant-information', label: 'Participant Information' },
  { href: '/data-upload', label: 'Data Upload Guidelines' },
  { href: '/about-us', label: 'About Us' },
  { href: '/faq', label: 'FAQ' },
  { href: '/contact', label: 'Contact' },
];

function isActive(pathname: string, href: string) {
  return href === '/' ? pathname === '/' : pathname.startsWith(href);
}

export function SiteHeader() {
  const { scrolled } = useScroll(10);
  const pathname = usePathname();
  const [isMobileMenuOpen, setIsMobileMenuOpen] = React.useState(false);

  const closeMenu = () => setIsMobileMenuOpen(false);

  return (
    <header
      className={cn(
        'sticky top-0 z-50 w-full border-b transition-colors duration-300',
        scrolled
          ? 'border-border/60 bg-background/80 shadow-sm backdrop-blur-md'
          : 'border-transparent bg-transparent'
      )}
    >
      <div className="container mx-auto flex h-20 items-center justify-between gap-4 px-4 sm:px-6">
        {/* Left: desktop URC logo */}
        <div className="flex items-center">
          <Link href="/" className="hidden shrink-0 items-center lg:flex" aria-label="Home">
            <Image src={StaticImages.urcLogo} alt="URC Logo" width={32} height={32} />
          </Link>
        </div>

        {/* Center: mobile logos / desktop nav */}
        <div className="flex flex-1 items-center justify-center">
          <div className="flex items-center space-x-6 lg:hidden">
            <Image src={StaticImages.urcLogo} alt="URC Logo" width={32} height={32} />
            <Image src={StaticImages.ucdLogo} alt="UCD Logo" width={32} height={32} />
          </div>
          <nav className="hidden items-center gap-0.5 lg:flex">
            {navLinks.map((link) => {
              const active = isActive(pathname, link.href);
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  aria-current={active ? 'page' : undefined}
                  className={cn(
                    'rounded-md px-3 py-2 text-sm font-medium transition-colors',
                    active
                      ? 'bg-primary/10 text-primary'
                      : 'text-muted-foreground hover:bg-foreground/5 hover:text-foreground'
                  )}
                >
                  {link.label}
                </Link>
              );
            })}
          </nav>
        </div>

        {/* Right: desktop UCD logo / mobile burger */}
        <div className="flex items-center">
          <div className="hidden shrink-0 items-center lg:flex">
            <Image src={StaticImages.ucdLogo} alt="UCD Logo" width={32} height={32} />
          </div>
          <div className="lg:hidden">
            <Sheet open={isMobileMenuOpen} onOpenChange={setIsMobileMenuOpen}>
              <SheetTrigger asChild>
                <Button variant="ghost" size="icon">
                  <Menu className="h-8 w-8 text-primary" />
                  <span className="sr-only">Open menu</span>
                </Button>
              </SheetTrigger>
              <SheetContent side="right" className="flex w-[78vw] max-w-xs flex-col p-6">
                <SheetHeader className="text-right">
                  <SheetTitle className="inline-block border-b-2 border-primary pb-1">
                    SCRIIPT
                  </SheetTitle>
                </SheetHeader>
                <nav className="flex flex-col gap-1 pt-6 text-right">
                  {navLinks.map((link) => {
                    const active = isActive(pathname, link.href);
                    return (
                      <Link
                        key={link.href}
                        href={link.href}
                        aria-current={active ? 'page' : undefined}
                        onClick={closeMenu}
                        className={cn(
                          'rounded-md px-3 py-2.5 text-base font-medium transition-colors',
                          active
                            ? 'bg-primary/10 text-primary'
                            : 'text-foreground hover:bg-foreground/5 hover:text-primary'
                        )}
                      >
                        {link.label}
                      </Link>
                    );
                  })}
                </nav>
              </SheetContent>
            </Sheet>
          </div>
        </div>
      </div>
    </header>
  );
}
