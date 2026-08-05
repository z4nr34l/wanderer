import { useCallback, useEffect, useMemo, useState } from 'react';
import { Dropdown } from 'primereact/dropdown';
import { InputTextarea } from 'primereact/inputtextarea';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import clsx from 'clsx';
import { WdButton } from '@/hooks/Mapper/components/ui-kit';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { OutCommand, SolarSystemConnection } from '@/hooks/Mapper/types';
import { useToast } from '@/hooks/Mapper/ToastProvider.tsx';
import {
  formatMass,
  MASS_STATUS_RANGES,
  parseRollingFits,
  RollingFit,
} from '@/hooks/Mapper/constants/rollingFits.ts';
import { UserSettingsRemoteProps } from '@/hooks/Mapper/constants/userSettings.ts';

type JumpPlan = {
  perJump: number;
  minJumps: number;
  maxJumps: number;
  overLimit: boolean;
};

const planJumps = (shipMass: number, remainingMin: number, remainingMax: number, jumpLimit: number): JumpPlan => ({
  perJump: shipMass,
  minJumps: shipMass > 0 ? Math.ceil(remainingMin / shipMass) : 0,
  maxJumps: shipMass > 0 ? Math.ceil(remainingMax / shipMass) : 0,
  overLimit: jumpLimit > 0 && shipMass > jumpLimit,
});

export interface RollingCalculatorProps {
  connection?: SolarSystemConnection;
  // mass of the passages recorded on this connection, when the map has any
  passedMass?: number;
  // mass of the passages recorded since the mass status was marked
  massSinceMark?: number;
}

export const RollingCalculator = ({
  connection,
  passedMass = 0,
  massSinceMark = 0,
}: RollingCalculatorProps) => {
  const {
    outCommand,
    data: { wormholesData },
    userRemoteSettings: { userRemoteSettings, setUserRemoteSettings },
  } = useMapRootState();

  const { show } = useToast();

  const [selectedFitId, setSelectedFitId] = useState<string | null>(null);
  const [holeType, setHoleType] = useState<string | null>(null);
  // marking the status the moment it flips pins the remaining mass to the top of the band, which
  // is a point rather than a range - that is how a hole gets rolled deliberately
  const [markedAtFlip, setMarkedAtFlip] = useState(true);
  const [showAddFit, setShowAddFit] = useState(false);
  const [fitName, setFitName] = useState('');
  const [fitText, setFitText] = useState('');
  const [busy, setBusy] = useState(false);

  const fits = useMemo(() => parseRollingFits(userRemoteSettings.rolling_fits), [userRemoteSettings.rolling_fits]);

  const fit = useMemo(
    () => fits.find(x => x.id === selectedFitId) ?? fits[0],
    [fits, selectedFitId],
  );

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

  const plans = useMemo(() => {
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

    return {
      range,
      usePassages,
      fromMark,
      remainingMin,
      remainingMax,
      cold: planJumps(
        fit.cold_mass,
        markedAtFlip ? remainingMin : remainingMin,
        markedAtFlip ? remainingMin : remainingMax,
        wormhole.max_mass_per_jump,
      ),
      hot: planJumps(
        fit.hot_mass,
        markedAtFlip ? remainingMin : remainingMin,
        markedAtFlip ? remainingMin : remainingMax,
        wormhole.max_mass_per_jump,
      ),
    };
  }, [connection, fit, markedAtFlip, massSinceMark, passedMass, wormhole]);

  const handleSaveFit = useCallback(async () => {
    setBusy(true);

    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const res: any = await outCommand({ type: OutCommand.parseFit, data: { fit: fitText } });

      if (!res?.fit) {
        show({ severity: 'error', summary: 'Fit', detail: res?.error ?? 'Could not read that fit.', life: 4000 });
        return;
      }

      const parsed: RollingFit = {
        id: `${Date.now()}`,
        name: fitName.trim() || res.fit.ship_name,
        ship_name: res.fit.ship_name,
        cold_mass: res.fit.cold_mass,
        hot_mass: res.fit.hot_mass,
      };

      const next = [...fits, parsed];

      await outCommand({
        type: OutCommand.updateUserSettings,
        data: { ...userRemoteSettings, [UserSettingsRemoteProps.rolling_fits]: next },
      });

      setUserRemoteSettings({ ...userRemoteSettings, [UserSettingsRemoteProps.rolling_fits]: next });
      setSelectedFitId(parsed.id);
      setShowAddFit(false);
      setFitName('');
      setFitText('');

      show({
        severity: 'success',
        summary: 'Fit',
        detail: `${parsed.ship_name}: ${formatMass(parsed.cold_mass)} cold, ${formatMass(parsed.hot_mass)} hot.`,
        life: 4000,
      });
    } finally {
      setBusy(false);
    }
  }, [fitName, fitText, fits, outCommand, setUserRemoteSettings, show, userRemoteSettings]);

  const handleRemoveFit = useCallback(async () => {
    if (!fit) {
      return;
    }

    const next = fits.filter(x => x.id !== fit.id);

    await outCommand({
      type: OutCommand.updateUserSettings,
      data: { ...userRemoteSettings, [UserSettingsRemoteProps.rolling_fits]: next },
    });

    setUserRemoteSettings({ ...userRemoteSettings, [UserSettingsRemoteProps.rolling_fits]: next });
    setSelectedFitId(next[0]?.id ?? null);
  }, [fit, fits, outCommand, setUserRemoteSettings, userRemoteSettings]);

  const renderPlan = (label: string, plan: JumpPlan) => (
    <div className="grid grid-cols-[54px_1fr_auto] items-center gap-2 text-[12px]">
      <span className="text-stone-400">{label}</span>
      <span className={clsx('font-mono', plan.overLimit ? 'text-red-400' : 'text-stone-200')}>
        {plan.overLimit
          ? 'too heavy for this hole'
          : plan.minJumps === plan.maxJumps
            ? `${plan.maxJumps} jumps`
            : `${plan.minJumps} - ${plan.maxJumps} jumps`}
      </span>
      <span className="text-stone-500">{formatMass(plan.perJump)}</span>
    </div>
  );

  return (
    <div className="flex flex-col gap-2">
        <div className="flex items-center gap-2">
          <Dropdown
            className="text-sm flex-1"
            value={fit?.id ?? null}
            options={fits.map(x => ({ label: `${x.name} (${x.ship_name})`, value: x.id }))}
            onChange={e => setSelectedFitId(e.value)}
            placeholder={fits.length ? 'Select a fit' : 'No fits yet'}
            emptyMessage="Paste a fit to get started"
          />
          <WdButton size="small" outlined icon="pi pi-plus" onClick={() => setShowAddFit(true)} />
          <WdButton size="small" outlined severity="danger" icon="pi pi-trash" disabled={!fit} onClick={handleRemoveFit} />
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

        {wormhole && !fit && (
          <span className="text-stone-500 text-[12px]">Add a fit to see how many jumps it takes.</span>
        )}

        {plans && wormhole && (
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between text-[12px]">
              <span className="text-stone-200 font-semibold">{wormhole.name}</span>
              <span className="text-stone-400">{plans.range.label}</span>
            </div>

            <div className="text-[11px] text-stone-500">
              {formatMass(wormhole.total_mass)} total, {formatMass(wormhole.max_mass_per_jump)} per jump, about{' '}
              {formatMass(plans.remainingMin)} - {formatMass(plans.remainingMax)} left
              {plans.usePassages && <span className="text-stone-400"> (narrowed by recorded passages)</span>}
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

            <div className="text-[11px] text-stone-500">
              {markedAtFlip
                ? `Counting from ${Math.round(plans.range.max * 100)}% left, the point the hole enters this status${
                    massSinceMark > 0 ? `, less ${formatMass(massSinceMark)} passed since` : ''
                  }.`
                : `A status on its own only gives a band - ${Math.round(plans.range.min * 100)}% to ${Math.round(
                    plans.range.max * 100,
                  )}% of total - so the jumps are a range. Plan for the high end.`}
            </div>

            <div className="border-b border-dotted border-stone-700/50" />

            {renderPlan('Cold', plans.cold)}
            {renderPlan('Hot', plans.hot)}
          </div>
        )}
      <Dialog
        header="Add a fit"
        visible={showAddFit}
        draggable={false}
        className="w-[520px]"
        onHide={() => setShowAddFit(false)}
      >
        <div className="flex flex-col gap-2">
          <InputText
            className="text-sm"
            value={fitName}
            onChange={e => setFitName(e.target.value)}
            placeholder="Name (defaults to the hull)"
          />
          <InputTextarea
            className="text-sm font-mono"
            rows={12}
            value={fitText}
            onChange={e => setFitText(e.target.value)}
            placeholder={'Paste an EFT fit here\n\n[Megathron, Rolling Mega]\nDamage Control II\n500MN Quad LiF Restrained Microwarpdrive'}
          />
          <span className="text-stone-500 text-[11px]">
            Masses come from EVE itself - the hull, plus the heaviest prop mod in the fit for the hot number.
          </span>
          <div className="flex justify-end">
            <WdButton size="small" label="Add" disabled={busy || fitText.trim() === ''} onClick={handleSaveFit} />
          </div>
        </div>
      </Dialog>
    </div>
  );
};
