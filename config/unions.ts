export type UnionStatus = 'live' | 'locked';

export type Union = {
  id: string;
  name: string;
  governingBody: string;
  teamIds: string[];
  accent: string;
  accentSecondary: string;
  crest?: string;
  /** Locked until a governance-cleared league/union aggregate is released. */
  status: UnionStatus;
};

export const unionDashboardTabs = [
  { id: 'overview', name: 'Overview' },
  { id: 'teams', name: 'Team Comparison' },
  { id: 'exposure', name: 'Exposure' },
  { id: 'common-injuries', name: 'Common Injuries' },
];

export const unions: Union[] = [
  {
    id: 'irfu',
    name: 'Ireland',
    governingBody: 'IRFU',
    teamIds: ['leinster', 'munster', 'ulster', 'connacht'],
    accent: '#009A44',
    accentSecondary: '#FFFFFF',
    crest: '/images/union-crests/irfu.svg',
    status: 'locked',
  },
  {
    id: 'wru',
    name: 'Wales',
    governingBody: 'WRU',
    teamIds: ['cardiff', 'dragons', 'ospreys', 'scarlets'],
    accent: '#D30731',
    accentSecondary: '#FFFFFF',
    crest: '/images/union-crests/wru.svg',
    status: 'locked',
  },
  {
    id: 'saru',
    name: 'South Africa',
    governingBody: 'SARU',
    teamIds: ['bulls', 'lions', 'sharks', 'stormers'],
    accent: '#007749',
    accentSecondary: '#FFB81C',
    crest: '/images/union-crests/saru.svg',
    status: 'locked',
  },
  {
    id: 'fir',
    name: 'Italy',
    governingBody: 'FIR',
    teamIds: ['benetton', 'zebre'],
    accent: '#008C45',
    accentSecondary: '#CD212A',
    crest: '/images/union-crests/fir.svg',
    status: 'locked',
  },
  {
    id: 'sru',
    name: 'Scotland',
    governingBody: 'SRU',
    teamIds: ['edinburgh', 'glasgow'],
    accent: '#005EB8',
    accentSecondary: '#FFFFFF',
    crest: '/images/union-crests/sru.svg',
    status: 'locked',
  },
];

export const getUnionById = (id: string): Union | undefined =>
  unions.find((union) => union.id === id);
