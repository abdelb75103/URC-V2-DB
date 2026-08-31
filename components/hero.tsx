import Image from 'next/image';
import { StaticImages } from '@/lib/placeholder-images';

export function Hero() {
  return (
    <div className="relative w-full h-80 sm:h-96 rounded-xl overflow-hidden mb-8 shadow-2xl">
      <Image
        src="/images/urc-hero2.webp"
        alt=""
        fill
        priority
        unoptimized
        sizes="(max-width: 1024px) calc(100vw - 32px), 1024px"
        className="object-cover"
      />
      {/* Blue tint + vignette layers */}
      <div className="absolute inset-0 bg-cyan-900/50" />
      <div className="absolute inset-0 bg-gradient-to-t from-black via-black/70 to-black/40" />
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,transparent_0%,rgba(0,0,0,0.8)_100%)]" />

      <div className="absolute inset-0 flex flex-col items-center justify-center text-center text-white px-4 sm:px-8">
        <div className="flex items-center justify-center gap-6 sm:gap-8 mb-6 sm:mb-8">
          <Image
            src={StaticImages.urcLogo}
            alt="URC Logo"
            width={64}
            height={64}
            className="drop-shadow-2xl w-12 h-12 sm:w-16 sm:h-16 hover:scale-110 transition-transform duration-300 object-contain"
          />
          <div className="w-px h-12 sm:h-16 bg-white/30" />
          <Image
            src={StaticImages.ucdLogo}
            alt="UCD Logo"
            width={64}
            height={64}
            className="drop-shadow-2xl w-12 h-12 sm:w-16 sm:h-16 hover:scale-[1.32] transition-transform duration-300 object-contain scale-[1.2]"
          />
        </div>

        <h1 className="text-6xl sm:text-7xl md:text-8xl lg:text-9xl font-black tracking-tight mb-4 sm:mb-6 drop-shadow-2xl">
          <span className="bg-gradient-to-r from-white via-cyan-100 to-white bg-clip-text text-transparent">
            SCRIIPT
          </span>
        </h1>

        <p className="text-base sm:text-lg md:text-xl lg:text-2xl font-light max-w-4xl leading-relaxed drop-shadow-xl text-white/95 tracking-wide">
          Surveillance of Continental Rugby
          <br className="hidden sm:block" />
          <span className="text-cyan-200 font-medium"> Injury-Illness and Performance Tracking</span>
        </p>
      </div>
    </div>
  );
}
