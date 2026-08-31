export type TeamStatus = 'live' | 'locked';

export type Team = {
  id: string;
  name: string;
  crest: string;
  accent: string;
  accentSecondary: string;
  /**
   * 'live'   -> a governance-cleared aggregate exists and the dashboard is open.
   * 'locked' -> no cleared aggregate yet; the tile renders as awaiting-data.
   * Only teams with a disclosure-reviewed export in content/reporting may be 'live'.
   */
  status: TeamStatus;
};

const CREST = '/images/Team Crests';

export const teams: Team[] = [
  // Ireland
  { id: 'connacht', name: 'Connacht', crest: `${CREST}/ConnachtRugby.svg.png`, accent: '#007A4D', accentSecondary: '#000000', status: 'live' },
  { id: 'leinster', name: 'Leinster', crest: `${CREST}/LeinsterRugby.svg.png`, accent: '#005596', accentSecondary: '#FFFFFF', status: 'live' },
  { id: 'munster', name: 'Munster', crest: `${CREST}/MunsterRugby.svg.png`, accent: '#D2232A', accentSecondary: '#FFFFFF', status: 'live' },
  { id: 'ulster', name: 'Ulster', crest: `${CREST}/UlsterRugby.svg.png`, accent: '#D2232A', accentSecondary: '#FFFFFF', status: 'live' },
  // Wales
  { id: 'cardiff', name: 'Cardiff', crest: `${CREST}/CardiffRugby.svg.png`, accent: '#00A3E0', accentSecondary: '#000000', status: 'live' },
  { id: 'dragons', name: 'Dragons', crest: `${CREST}/DragonsRugby.svg.png`, accent: '#D2232A', accentSecondary: '#FFC72C', status: 'live' },
  { id: 'ospreys', name: 'Ospreys', crest: `${CREST}/OspreysRugby.svg.png`, accent: '#000000', accentSecondary: '#FFFFFF', status: 'live' },
  { id: 'scarlets', name: 'Scarlets', crest: `${CREST}/ScarletsRugby.svg.png`, accent: '#D2232A', accentSecondary: '#FFFFFF', status: 'live' },
  // South Africa
  { id: 'bulls', name: 'Bulls', crest: `${CREST}/BullsRugby.svg.png`, accent: '#009DDC', accentSecondary: '#FFFFFF', status: 'live' },
  { id: 'lions', name: 'Lions', crest: `${CREST}/LionsRugbylogo.svg.png`, accent: '#D2232A', accentSecondary: '#FFFFFF', status: 'live' },
  { id: 'sharks', name: 'Sharks', crest: `${CREST}/SharksRugby.svg.png`, accent: '#000000', accentSecondary: '#FFFFFF', status: 'live' },
  { id: 'stormers', name: 'Stormers', crest: `${CREST}/StormersRugby.svg.png`, accent: '#005596', accentSecondary: '#FFFFFF', status: 'live' },
  // Italy
  { id: 'benetton', name: 'Benetton', crest: `${CREST}/BenettonRugby.svg.png`, accent: '#009639', accentSecondary: '#FFFFFF', status: 'live' },
  { id: 'zebre', name: 'Zebre', crest: `${CREST}/ZebreRugby.svg.png`, accent: '#FFC72C', accentSecondary: '#000000', status: 'live' },
  // Scotland
  { id: 'edinburgh', name: 'Edinburgh', crest: `${CREST}/Edinburgh_Rugby_logo_2018.svg.png`, accent: '#002D56', accentSecondary: '#E87722', status: 'live' },
  { id: 'glasgow', name: 'Glasgow', crest: `${CREST}/GlasgowRugby.svg.png`, accent: '#00A3E0', accentSecondary: '#000000', status: 'live' },
];

export const getTeamById = (id: string): Team | undefined =>
  teams.find((team) => team.id === id);
