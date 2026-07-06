'use client';

import * as React from 'react';
import Image from 'next/image';
import Link from 'next/link';
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

export function SiteHeader() {
  const { scrolled } = useScroll(10);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = React.useState(false);

  const closeMenu = () => setIsMobileMenuOpen(false);

  return (
    <header
      className={cn(
        'sticky top-0 z-50 w-full transition-all duration-300',
        scrolled
          ? 'bg-background/90 shadow-md backdrop-blur-sm -translate-y-full'
          : 'bg-transparent translate-y-0'
      )}
    >
      <div className="container mx-auto flex h-16 items-center justify-between px-4 sm:px-6">
        {/* Left: desktop URC logo */}
        <div className="flex items-center">
          <Link href="/" className="hidden md:flex items-center" aria-label="Home">
            <Image src={StaticImages.urcLogo} alt="URC Logo" width={32} height={32} />
          </Link>
        </div>

        {/* Center: mobile logos / desktop nav */}
        <div className="flex flex-1 items-center justify-center">
          <div className="flex md:hidden items-center space-x-6">
            <Image src={StaticImages.urcLogo} alt="URC Logo" width={32} height={32} />
            <Image src={StaticImages.ucdLogo} alt="UCD Logo" width={32} height={32} />
          </div>
          <nav className="hidden md:flex items-center space-x-1 text-sm font-medium">
            {navLinks.map((link) => (
              <Button key={link.href} variant="link" className="text-foreground" asChild>
                <Link href={link.href}>{link.label}</Link>
              </Button>
            ))}
          </nav>
        </div>

        {/* Right: desktop UCD logo / mobile burger */}
        <div className="flex items-center">
          <div className="hidden md:flex items-center">
            <Image src={StaticImages.ucdLogo} alt="UCD Logo" width={32} height={32} />
          </div>
          <div className="md:hidden">
            <Sheet open={isMobileMenuOpen} onOpenChange={setIsMobileMenuOpen}>
              <SheetTrigger asChild>
                <Button variant="ghost" size="icon">
                  <Menu className="h-8 w-8 text-primary" />
                  <span className="sr-only">Open menu</span>
                </Button>
              </SheetTrigger>
              <SheetContent side="right" className="w-[70vw] flex flex-col p-6">
                <SheetHeader className="text-right">
                  <SheetTitle className="pb-1 border-b-2 border-primary inline-block">
                    SCRIIPT
                  </SheetTitle>
                </SheetHeader>
                <nav className="flex flex-col pt-6 gap-6 text-lg font-medium text-right">
                  {navLinks.map((link) => (
                    <Link
                      key={link.href}
                      href={link.href}
                      className="text-foreground hover:text-primary transition-colors"
                      onClick={closeMenu}
                    >
                      {link.label}
                    </Link>
                  ))}
                </nav>
              </SheetContent>
            </Sheet>
          </div>
        </div>
      </div>
    </header>
  );
}
