export type RollingFit = {
  id: string;
  name: string;
  ship_name: string;
  // kilograms, as EVE reports them
  cold_mass: number;
  hot_mass: number;
};

export const parseRollingFits = (raw: unknown): RollingFit[] => {
  if (typeof raw === 'string') {
    try {
      return parseRollingFits(JSON.parse(raw));
    } catch {
      return [];
    }
  }

  if (!Array.isArray(raw)) {
    return [];
  }

  return raw.filter(
    (fit): fit is RollingFit =>
      !!fit &&
      typeof fit === 'object' &&
      typeof (fit as RollingFit).id === 'string' &&
      typeof (fit as RollingFit).name === 'string' &&
      typeof (fit as RollingFit).cold_mass === 'number' &&
      typeof (fit as RollingFit).hot_mass === 'number',
  );
};

export const formatMass = (kilograms: number): string => {
  if (kilograms >= 1_000_000) {
    return `${(kilograms / 1_000_000).toFixed(1)} kt`;
  }

  return `${Math.round(kilograms / 1000)} t`;
};

// What is left in a hole for a given mass status, as a share of its total mass. The game only
// tells us which band it is in, so every answer is a range.
export const MASS_STATUS_RANGES: Record<number, { min: number; max: number; label: string }> = {
  0: { min: 0.5, max: 1, label: 'Stable' },
  1: { min: 0.1, max: 0.5, label: 'Half' },
  2: { min: 0, max: 0.1, label: 'Verge of collapse' },
};
