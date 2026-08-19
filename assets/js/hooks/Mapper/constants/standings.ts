import { SovereigntyInfo } from '@/hooks/Mapper/types';

/**
 * Standings people set for the alliances they care about, so a null sec chain reads at a glance:
 * whose space is safe to cross and whose is not.
 *
 * The number is an EVE standing, and the colour follows from it the way the overview does -
 * -10 is a killer, -5 is someone to watch, +5 and up is a friend.
 */
export enum StandingBand {
  danger = 'danger',
  warning = 'warning',
  neutral = 'neutral',
  friendly = 'friendly',
}

export type AllianceStanding = {
  id: string;
  // ticker or alliance name, as typed
  alliance: string;
  standing: number;
};

export const STANDING_RANGE = { min: -10, max: 10 };

export const STANDING_BAND_LABELS: Record<StandingBand, string> = {
  [StandingBand.danger]: 'Danger',
  [StandingBand.warning]: 'Warning',
  [StandingBand.neutral]: 'Neutral',
  [StandingBand.friendly]: 'Friendly',
};

// themeable, same as the rest of the node
export const STANDING_COLORS: Record<StandingBand, string> = {
  [StandingBand.danger]: 'var(--rf-node-sov-danger, #b91c1c)',
  [StandingBand.warning]: 'var(--rf-node-sov-warning, #c2410c)',
  [StandingBand.neutral]: 'var(--rf-node-sov-neutral, #52525b)',
  [StandingBand.friendly]: 'var(--rf-node-sov-friendly, #1d4ed8)',
};

export const DEFAULT_SOVEREIGNTY_COLOR = STANDING_COLORS[StandingBand.neutral];

/**
 * Which band a standing falls in. -10 and below is danger, -5 down to (but not including) -10 is
 * warning, +5 and above is friendly, and the middle is left neutral.
 */
export const standingBand = (standing: number): StandingBand => {
  if (standing <= -10) {
    return StandingBand.danger;
  }

  if (standing <= -5) {
    return StandingBand.warning;
  }

  if (standing >= 5) {
    return StandingBand.friendly;
  }

  return StandingBand.neutral;
};

export const createStandingId = () => Math.random().toString(36).slice(2, 10);

/**
 * Standings are kept per character: two characters in different alliances look at the same map
 * and see different space, so switching character has to switch what the map says.
 *
 * The shared bucket is what a character without its own list falls back on, and is where the
 * standings of anyone who set them before this was per character ended up.
 */
export const SHARED_STANDINGS = 'shared';

export type StandingsByCharacter = Record<string, AllianceStanding[]>;

export const parseStandingsByCharacter = (value: unknown): StandingsByCharacter => {
  // a flat list is what this setting used to be, and applied to everyone
  if (Array.isArray(value)) {
    return { [SHARED_STANDINGS]: parseAllianceStandings(value) };
  }

  if (!value || typeof value !== 'object') {
    return {};
  }

  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>).map(([key, entries]) => [
      key,
      parseAllianceStandings(entries),
    ]),
  );
};

export const standingsFor = (byCharacter: StandingsByCharacter, characterEveId?: string | null): AllianceStanding[] =>
  (characterEveId ? byCharacter[characterEveId] : undefined) ?? byCharacter[SHARED_STANDINGS] ?? [];

const clamp = (value: number) => Math.min(STANDING_RANGE.max, Math.max(STANDING_RANGE.min, value));

export const parseAllianceStandings = (value: unknown): AllianceStanding[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((x): x is AllianceStanding => !!x && typeof x === 'object')
    .map(x => ({
      id: typeof x.id === 'string' && x.id !== '' ? x.id : createStandingId(),
      alliance: typeof x.alliance === 'string' ? x.alliance : '',
      standing: Number.isFinite(Number(x.standing)) ? clamp(Number(x.standing)) : 0,
    }));
};

/**
 * An entry matches on the ticker or the alliance name, either way round and either case, so
 * "frt", "FRT" and "Fraternity." all land on the same alliance.
 */
export const findStanding = (
  sovereignty: SovereigntyInfo | null | undefined,
  standings: AllianceStanding[],
): number | undefined => {
  if (!sovereignty) {
    return undefined;
  }

  const ticker = sovereignty.alliance_ticker?.toLowerCase();
  const name = sovereignty.alliance_name?.toLowerCase();

  return standings.find(x => {
    const match = x.alliance.trim().toLowerCase();

    return match !== '' && (match === ticker || match === name);
  })?.standing;
};

export const sovereigntyColor = (
  sovereignty: SovereigntyInfo | null | undefined,
  standings: AllianceStanding[],
): string => {
  const standing = findStanding(sovereignty, standings);

  return standing === undefined ? DEFAULT_SOVEREIGNTY_COLOR : STANDING_COLORS[standingBand(standing)];
};
