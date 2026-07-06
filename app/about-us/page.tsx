import { PageHeader } from '@/components/dashboard/page-header';
import { ProfileCard } from '@/components/profile-card';

export const metadata = { title: 'About Us — SCRIIPT' };

const teamMembers = [
  {
    name: 'Greg Hawe',
    title: 'Lead Researcher & Senior Musculoskeletal Physiotherapist',
    imageUrl: '/images/Greg.jpeg',
    imageHint: 'professional headshot',
    bio: [
      'Greg is a highly qualified sports physiotherapy and musculoskeletal health specialist with extensive experience across elite sporting and healthcare environments. He holds undergraduate degrees in Health & Performance Science and Physiotherapy from Dublin, and began his professional career in Singapore, working across public health systems, private practice, and professional sport.',
      'During this time, he commenced his MSc in Sports Physiotherapy with the University of Bath. Since returning to Ireland following the pandemic, Greg has continued to work across both public and private sectors, while also serving as Lead Physiotherapist for the Leinster Women’s rugby team.',
      'He is currently a Senior MSK Physiotherapist with Vhi and began his PhD in January 2025 under the supervision of Dr. Nicol van Dyk. His doctoral research focuses on the relationship between injury, illness, and performance in elite rugby union—a natural fit given his 20 years of involvement in the sport as both a player and practitioner.',
      'In addition, Greg has completed formal training in health project management, equipping him with the skills to contribute effectively to the design, delivery, and governance of multidisciplinary research initiatives such as the SCRIIPT Project.',
    ],
  },
  {
    name: 'Nicol Van Dyk',
    title: 'Lead Researcher & Assistant Professor (Ad Astra Fellow)',
    subtitle:
      'School of Public Health, Physiotherapy & Sport Science, University College Dublin',
    imageUrl: '/images/Nicol.png',
    imageHint: 'professional headshot',
    imagePosition: 'object-top md:object-center',
    bio: [
      'Nicol is an emerging research and performance leader with vast experience across elite sport cultures. After completing his undergraduate and masters degree in physiotherapy at Stellenbosch University in South Africa, Nicol joined the prestigious Aspetar Orthopaedic and Sports Medicine Hospital.',
      'He undertook a PhD while maintaining his clinical workload together with increasing leadership responsibilities at Aspetar. His PhD on hamstring injuries had influence world-wide.',
      'Nicol has participated in policy development, joining the Musculoskeletal Task Force for the Department of Public Health, Doha, Qatar. He has consulted on pressing social issues such as participating in a white paper on Child Labour in Sport as part of Protecting the Rights of Child Athletes (Centre for Sport and Human Rights), and led the development of strategy around Research and Discovery for elite sporting bodies.',
      'He is a data strategy consultant and industry mentor in sport and healthcare technology, advising and mentoring early start ups through their initial growth as well as consulting developed companies looking to expand their market opportunity. His unique blend of clinical experience in musculoskeletal health within different cultures and context, as the applied research training in real world environments allows him to identify unique value propositions in different conditions.',
    ],
  },
  {
    name: 'AbdelRahman Babiker',
    title: 'Data Analyst & PhD Candidate',
    imageUrl: '/images/Abdel.png',
    imageHint: 'professional headshot',
    bio: [
      'AbdelRahman Babiker is the lead data analyst for the URC SCRIIPT project. A PhD candidate in sports epidemiology at University College Dublin, he draws on experience as a former high performance player and later a strength and conditioning coach to bring a grounded, applied view to how data supports medical and coaching staff.',
      'With a Master’s in engineering and a degree in Health and Performance Science from UCD, AbdelRahman brings a rare blend of technical rigour and applied sport insight. His PhD focuses on sports injury epidemiology, and his time as a player and strength & conditioning coach, at the elite level, keeps his analysis grounded in the realities of the training ground and the medical room.',
    ],
  },
];

export default function AboutUsPage() {
  return (
    <div className="flex flex-col">
      <PageHeader title="About Us" />
      <div className="flex-1 p-4 sm:p-6">
        <div className="mx-auto max-w-6xl space-y-8">
          {teamMembers.map((member, index) => (
            <ProfileCard key={member.name} {...member} reverse={index % 2 !== 0} />
          ))}
        </div>
      </div>
    </div>
  );
}
