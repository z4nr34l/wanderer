import { useEffect, useMemo, useState } from 'react';
import { Dropdown } from 'primereact/dropdown';
import clsx from 'clsx';
import { WdButton } from '@/hooks/Mapper/components/ui-kit';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { SolarSystemConnection } from '@/hooks/Mapper/types';
import { formatMass, MASS_STATUS_RANGES } from '@/hooks/Mapper/constants/rollingFits.ts';
import { ShipFitRequest, useShipFits } from '@/hooks/Mapper/hooks/useShipFits.ts';
import { JumpCount, jumpsToTarget, TARGETS } from './jumps.ts';

const FIT_ERRORS: Record<string, string> = {
  no_scope: 'EVE will not show this ship - reconnect the character to grant asset access.',
  no_ship: 'EVE is not reporting a ship for this character.',
  character_not_tracked: 'Track this character on the map to read its ship.',
  assets_disabled: 'This map cannot read ships from EVE.',
};

const renderCount = (count: JumpCount) => {
  if (count.overLimit) {
    return <span className="text-red-400">too heavy</span>;
  }

  if (count.max === 0) {
    return <span className="text-emerald-400">done</span>;
  }

  return (
    <span className="font-mono text-stone-200">
      {count.min === count.max ? count.max : `${count.min} - ${count.max}`}
    </span>
  );
};

export interface RollingCalculatorProps {
  connection?: SolarSystemConnection;
  // mass of the passages recorded on this connection, when the map has any
  passedMass?: number;
  // mass of the passages recorded since the mass status was marked
  massSinceMark?: number;
}

export const RollingCalculator = ({ connection, passedMass = 0, massSinceMark = 0 }: RollingCalculatorProps) => {
  const {
    outCommand,
    data: { wormholesData, characters, userCharacters, mainCharacterEveId, followingCharacterEveId },
  } = useMapRootState();

  const [holeType, setHoleType] = useState<string | null>(null);
  // marking the status the moment it flips pins the remaining mass to the top of the band, which
  // is a point rather than a range - that is how a hole gets rolled deliberately
  const [markedAtFlip, setMarkedAtFlip] = useState(true);

  // rolling is done in whatever the character is flying, so that ship is what gets weighed
  const character = useMemo(() => {
    const eveId = mainCharacterEveId ?? followingCharacterEveId;

    if (!eveId || !userCharacters.includes(eveId)) {
      return undefined;
    }

    return characters.find(x => x.eve_id === eveId && x.ship);
  }, [characters, followingCharacterEveId, mainCharacterEveId, userCharacters]);

  const request = useMemo<ShipFitRequest | undefined>(
    () =>
      character
        ? {
            characterEveId: character.eve_id,
            shipKey: `${character.ship?.ship_type_id}:${character.ship?.ship_name}`,
          }
        : undefined,
    [character],
  );

  const requests = useMemo(() => (request ? [request] : []), [request]);
  const { fitFor, errorFor, refresh } = useShipFits(outCommand, requests);

  const fit = request ? fitFor(request) : undefined;
  const fitError = request ? errorFor(request) : undefined;

  const holeOptions = useMemo(
    () =>
      Object.values(wormholesData)
        .map(x => ({ label: `${x.name} (${formatMass(x.total_mass)})`, value: x.name }))
        .sort((a, b) => a.label.localeCompare(b.label)),
    [wormholesData],
  );

  // most connections have no wormhole type recorded, so the hole can be picked by hand and the
  // recorded type is only a starting point
  const wormhole = useMemo(() => {
    const name = holeType ?? connection?.wormhole_type;

    return name ? wormholesData[name] : undefined;
  }, [connection, holeType, wormholesData]);

  useEffect(() => {
    setHoleType(connection?.wormhole_type ?? null);
  }, [connection?.source, connection?.target, connection?.wormhole_type]);

  const plan = useMemo(() => {
    if (!wormhole || !fit) {
      return undefined;
    }

    const range = MASS_STATUS_RANGES[connection?.mass_status ?? 0] ?? MASS_STATUS_RANGES[0];

    // the status only says which band the hole is in, so the answer is a range. Passages the map
    // recorded can pull the top of that range down: whatever went through is no longer there.
    const bandMin = wormhole.total_mass * range.min;
    const bandMax = wormhole.total_mass * range.max;
    const afterPassages = wormhole.total_mass - passedMass;
    const usePassages = passedMass > 0 && afterPassages < bandMax;

    const remainingMax = usePassages ? Math.max(afterPassages, bandMin) : bandMax;

    // marked at the flip the hole sat at the top of the band, and everything that passed since
    // has come off it
    const fromMark = Math.max(bandMax - massSinceMark, 0);
    const remainingMin = markedAtFlip ? Math.min(fromMark, remainingMax) : bandMin;

    const rows = TARGETS.map(target => {
      const targetMass = wormhole.total_mass * target.share;

      return {
        ...target,
        cold: jumpsToTarget(remainingMin, remainingMax, targetMass, fit.cold_mass, wormhole.max_mass_per_jump),
        hot: jumpsToTarget(remainingMin, remainingMax, targetMass, fit.hot_mass, wormhole.max_mass_per_jump),
      };
    });

    return { range, usePassages, remainingMin, remainingMax, rows };
  }, [connection, fit, markedAtFlip, massSinceMark, passedMass, wormhole]);

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center justify-between gap-2 text-[12px]">
        {fit ? (
          <>
            <span className="text-stone-200 truncate">{fit.ship_name}</span>
            <span className="text-stone-500 font-mono whitespace-nowrap">
              {formatMass(fit.cold_mass)} cold / {formatMass(fit.hot_mass)} hot
            </span>
          </>
        ) : (
          <span className="text-stone-500">
            {fitError ? (FIT_ERRORS[fitError] ?? 'Could not read the ship from EVE.') : 'Reading your ship from EVE...'}
          </span>
        )}

        {request && <WdButton size="small" outlined icon="pi pi-refresh" onClick={() => refresh(request)} />}
      </div>

      <Dropdown
        className="text-sm"
        value={wormhole?.name ?? null}
        options={holeOptions}
        onChange={e => setHoleType(e.value)}
        filter
        placeholder="Hole type"
        emptyMessage="No wormhole data"
      />

      {!wormhole && (
        <span className="text-stone-500 text-[12px]">
          No hole type recorded on this connection - pick one to get its mass.
        </span>
      )}

      {plan && wormhole && (
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between text-[12px]">
            <span className="text-stone-200 font-semibold">{wormhole.name}</span>
            <span className="text-stone-400">{plan.range.label}</span>
          </div>

          <div className="text-[11px] text-stone-500">
            {formatMass(wormhole.total_mass)} total, {formatMass(wormhole.max_mass_per_jump)} per jump, about{' '}
            {formatMass(plan.remainingMin)}
            {plan.remainingMin === plan.remainingMax ? '' : ` - ${formatMass(plan.remainingMax)}`} left
            {plan.usePassages && <span className="text-stone-400"> (less what has gone through)</span>}
          </div>

          <label className="flex items-center gap-2 text-[11px] text-stone-400 select-none cursor-pointer">
            <input
              type="checkbox"
              checked={markedAtFlip}
              onChange={e => setMarkedAtFlip(e.target.checked)}
              className="cursor-pointer"
            />
            Status was marked the moment it flipped
          </label>

          <div className="border-b border-dotted border-stone-700/50" />

          <div className="grid grid-cols-[1fr_auto_auto] gap-x-3 gap-y-1 text-[12px] items-center">
            <span />
            <span className="text-sky-300 text-[11px] uppercase tracking-wide justify-self-end">cold</span>
            <span className="text-orange-300 text-[11px] uppercase tracking-wide justify-self-end">hot</span>

            {plan.rows.map(row => (
              <Row key={row.key} label={row.label} cold={row.cold} hot={row.hot} />
            ))}
          </div>

          <div className="text-[11px] text-stone-500">
            Jumps left in this ship, counted off the passages already recorded. Mark each one cold or hot in the list
            above, and set the mass status when the hole changes colour - both narrow the count.
          </div>
        </div>
      )}
    </div>
  );
};

const Row = ({ label, cold, hot }: { label: string; cold: JumpCount; hot: JumpCount }) => (
  <>
    <span className={clsx('text-stone-400')}>{label}</span>
    <span className="justify-self-end">{renderCount(cold)}</span>
    <span className="justify-self-end">{renderCount(hot)}</span>
  </>
);
