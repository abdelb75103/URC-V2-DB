'use client';

import { useState, useEffect } from 'react';

export function useScroll(threshold: number = 10) {
  const [scrolled, setScrolled] = useState(false);
  const [scrollDir, setScrollDir] = useState<'up' | 'down'>('down');

  useEffect(() => {
    let lastY = window.scrollY;
    const onScroll = () => {
      const y = window.scrollY;
      setScrolled(y > threshold);
      setScrollDir(y > lastY ? 'down' : 'up');
      lastY = y;
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, [threshold]);

  return { scrolled, scrollDir };
}
