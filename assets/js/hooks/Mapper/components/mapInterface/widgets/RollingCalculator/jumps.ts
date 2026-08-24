export type JumpCount = { min: number; max: number; overLimit: boolean };

// where the hole has to be taken, as a share of its total mass left
export const TARGETS = [
  { key: 'half', label: 'To half', share: 0.5 },
  { key: 'critical', label: 'To critical', share: 0.1 },
  { key: 'collapse', label: 'To collapse', share: 0 },
];

/**
 * How many jumps in a ship of this mass it takes to bring a hole down to a target mass.
 *
 * The remaining mass is a range whenever the map cannot pin it to a point, so the answer is one
 * too - the low end is what it takes if the hole is at its emptiest, the high end if it is not.
 */
export const jumpsToTarget = (
  remainingMin: number,
  remainingMax: number,
  target: number,
  shipMass: number,
  jumpLimit: number,
): JumpCount => ({
  min: shipMass > 0 ? Math.ceil(Math.max(remainingMin - target, 0) / shipMass) : 0,
  max: shipMass > 0 ? Math.ceil(Math.max(remainingMax - target, 0) / shipMass) : 0,
  overLimit: jumpLimit > 0 && shipMass > jumpLimit,
});
