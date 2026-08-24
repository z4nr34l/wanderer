// Mass helpers for rolling. Ships are read from EVE rather than pasted in, so nothing here
// knows about saved fits.

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
