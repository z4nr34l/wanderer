import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { InputText } from 'primereact/inputtext';
import { InputNumber } from 'primereact/inputnumber';
import { Toast } from 'primereact/toast';
import { WdButton } from '@/hooks/Mapper/components/ui-kit';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { OutCommand } from '@/hooks/Mapper/types';
import { useMapSettings } from '../MapSettingsProvider';
import { UserSettingsRemoteProps } from '../types';
import {
  AllianceStanding,
  createStandingId,
  parseAllianceStandings,
  STANDING_BAND_LABELS,
  STANDING_COLORS,
  STANDING_RANGE,
  standingBand,
} from '@/hooks/Mapper/constants/standings.ts';

type StandingRowProps = {
  entry: AllianceStanding;
  onChange: (patch: Partial<AllianceStanding>) => void;
  onRemove: () => void;
};

const StandingRow = ({ entry, onChange, onRemove }: StandingRowProps) => {
  const [alliance, setAlliance] = useState(entry.alliance);

  useEffect(() => setAlliance(entry.alliance), [entry.alliance]);

  return (
    <div className="grid grid-cols-[auto_1fr_auto_auto] items-center gap-2 shrink-0">
      <span
        className="w-[14px] h-[14px] rounded-sm border border-stone-700"
        style={{ backgroundColor: STANDING_COLORS[standingBand(entry.standing)] }}
      />

      <InputText
        className="text-sm w-full py-1 px-2"
        value={alliance}
        onChange={e => setAlliance(e.target.value)}
        onBlur={() => alliance !== entry.alliance && onChange({ alliance })}
        placeholder="Ticker or alliance name"
      />

      <div className="flex items-center gap-2">
        <InputNumber
          className="text-sm"
          inputClassName="text-sm w-[62px]"
          value={entry.standing}
          min={STANDING_RANGE.min}
          max={STANDING_RANGE.max}
          minFractionDigits={0}
          maxFractionDigits={1}
          showButtons
          onValueChange={e => onChange({ standing: e.value ?? 0 })}
        />
        <span className="text-stone-400 text-[11px] w-[54px]">{STANDING_BAND_LABELS[standingBand(entry.standing)]}</span>
      </div>

      <WdButton
        size="small"
        outlined
        severity="danger"
        icon="pi pi-trash"
        className="text-xs py-1 px-2 h-auto min-h-[24px]"
        onClick={onRemove}
      />
    </div>
  );
};

type ImportedStanding = { alliance: string; name?: string | null; standing: number };

export const StandingsSettings = () => {
  const { settings, updateSetting } = useMapSettings();
  const { outCommand } = useMapRootState();
  const toast = useRef<Toast | null>(null);
  const [importing, setImporting] = useState(false);

  const standings = useMemo(
    () => parseAllianceStandings(settings.sovereignty_standings),
    [settings.sovereignty_standings],
  );

  const save = useCallback(
    (next: AllianceStanding[]) => updateSetting(UserSettingsRemoteProps.sovereignty_standings, next),
    [updateSetting],
  );

  const handleChange = useCallback(
    (index: number, patch: Partial<AllianceStanding>) =>
      save(standings.map((x, i) => (i === index ? { ...x, ...patch } : x))),
    [save, standings],
  );

  const handleRemove = useCallback(
    (index: number) => save(standings.filter((_, i) => i !== index)),
    [save, standings],
  );

  const handleAdd = useCallback(
    () => save([...standings, { id: createStandingId(), alliance: '', standing: STANDING_RANGE.min }]),
    [save, standings],
  );

  // the alliance already keeps standings; this pulls them in rather than making people retype
  const handleImport = useCallback(async () => {
    setImporting(true);

    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const res: any = await outCommand({ type: OutCommand.importAllianceStandings, data: null });

      if (!res?.standings) {
        throw new Error(res?.error ?? 'Empty response');
      }

      const imported: ImportedStanding[] = res.standings;
      const sources: string[] = res.sources ?? [];

      // anything typed by hand for an alliance the contact list also covers gives way to it
      const byAlliance = new Map(standings.map(x => [x.alliance.trim().toLowerCase(), x]));

      imported.forEach(x => {
        const key = x.alliance.trim().toLowerCase();
        const existing = byAlliance.get(key);

        byAlliance.set(key, {
          id: existing?.id ?? createStandingId(),
          alliance: existing?.alliance ?? x.alliance,
          standing: x.standing,
        });
      });

      await save([...byAlliance.values()]);

      toast.current?.show({
        severity: 'success',
        summary: 'Standings',
        detail: imported.length
          ? `Took ${imported.length} alliance standings from the ${sources.join(' and ')} contact list${
              sources.length > 1 ? 's' : ''
            }.`
          : 'Those contact lists have no alliance entries.',
        life: 4000,
      });
    } catch (error) {
      toast.current?.show({
        severity: 'error',
        summary: 'Standings',
        detail: error instanceof Error ? error.message : 'Could not read the alliance contact list.',
        life: 6000,
      });
    } finally {
      setImporting(false);
    }
  }, [outCommand, save, standings]);

  return (
    <div className="w-full h-full min-h-0 flex flex-col gap-3 overflow-y-auto custom-scrollbar pr-1">
      <span className="text-stone-400 text-[12px] shrink-0">
        Colours the sovereignty ticker under null sec systems. Match on the ticker or the full alliance name -
        &quot;FRT&quot; and &quot;Fraternity.&quot; both work. Standings follow the overview: -10 and below is danger,
        -5 and below is warning, +5 and above is friendly. Anything not listed stays neutral.
      </span>

      <div className="grid grid-cols-[auto_1fr_auto_auto] items-center gap-2 text-stone-500 text-[10px] uppercase tracking-wider shrink-0">
        <span />
        <span>Alliance</span>
        <span>Standing</span>
        <span />
      </div>

      <div className="flex flex-col gap-2 shrink-0">
        {standings.map((entry, index) => (
          <StandingRow
            key={entry.id}
            entry={entry}
            onChange={patch => handleChange(index, patch)}
            onRemove={() => handleRemove(index)}
          />
        ))}
      </div>

      {standings.length === 0 && (
        <span className="text-stone-500 text-[12px] shrink-0">No alliances set - every holder shows neutral.</span>
      )}

      <div className="flex items-center gap-2 shrink-0">
        <WdButton size="small" outlined icon="pi pi-plus" label="Add alliance" onClick={handleAdd} />
        <WdButton
          size="small"
          outlined
          icon="pi pi-cloud-download"
          label="Import from alliance"
          disabled={importing}
          onClick={handleImport}
        />
      </div>

      <span className="text-stone-500 text-[11px] shrink-0">
        Importing reads the contact lists of the characters tracked on this map - personal, corporation and alliance.
        A character can always read its own; the corporation and alliance lists need the roles ESI asks for. Where they
        disagree the alliance wins, then the corporation. Characters added before these scopes existed need
        re-authenticating.
      </span>

      <Toast ref={toast} />
    </div>
  );
};
