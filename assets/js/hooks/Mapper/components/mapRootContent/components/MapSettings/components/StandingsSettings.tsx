import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { InputText } from 'primereact/inputtext';
import { InputNumber } from 'primereact/inputnumber';
import { Toast } from 'primereact/toast';
import { WdButton } from '@/hooks/Mapper/components/ui-kit';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { OutCommand } from '@/hooks/Mapper/types';
import { useMapSettings } from '../MapSettingsProvider';
import { UserSettingsRemoteProps } from '../types';
import { Dropdown } from 'primereact/dropdown';
import {
  AllianceStanding,
  createStandingId,
  parseStandingsByCharacter,
  SHARED_STANDINGS,
  STANDING_BAND_LABELS,
  STANDING_COLORS,
  STANDING_RANGE,
  standingBand,
  StandingsByCharacter,
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

type ImportResult = {
  character_eve_id: string;
  character_name: string;
  standings: ImportedStanding[];
  sources: string[];
};

export const StandingsSettings = () => {
  const { settings, updateSetting } = useMapSettings();
  const {
    outCommand,
    data: { characters, userCharacters, followingCharacterEveId, mainCharacterEveId },
  } = useMapRootState();
  const toast = useRef<Toast | null>(null);
  const [importing, setImporting] = useState(false);

  const byCharacter = useMemo(
    () => parseStandingsByCharacter(settings.sovereignty_standings),
    [settings.sovereignty_standings],
  );

  // your own characters, plus a shared bucket for anyone without a list of their own
  const characterOptions = useMemo(
    () => [
      { label: 'All characters', value: SHARED_STANDINGS },
      ...characters
        .filter(x => userCharacters.includes(x.eve_id))
        .map(x => ({ label: x.name, value: x.eve_id })),
    ],
    [characters, userCharacters],
  );

  const [selected, setSelected] = useState<string>(
    () => followingCharacterEveId ?? mainCharacterEveId ?? SHARED_STANDINGS,
  );

  const standings = useMemo(() => byCharacter[selected] ?? [], [byCharacter, selected]);

  const saveAll = useCallback(
    (next: StandingsByCharacter) => updateSetting(UserSettingsRemoteProps.sovereignty_standings, next),
    [updateSetting],
  );

  const save = useCallback(
    (next: AllianceStanding[]) => saveAll({ ...byCharacter, [selected]: next }),
    [byCharacter, saveAll, selected],
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

      if (!res?.results) {
        throw new Error(res?.error ?? 'Empty response');
      }

      const results: ImportResult[] = res.results;

      // each character keeps its own list, so a character in another alliance is not overwritten
      // by one that happens to have been imported last
      const next: StandingsByCharacter = { ...byCharacter };

      results.forEach(result => {
        const existing = new Map((byCharacter[result.character_eve_id] ?? []).map(x => [x.alliance.trim().toLowerCase(), x]));

        result.standings.forEach(x => {
          const key = x.alliance.trim().toLowerCase();
          const had = existing.get(key);

          existing.set(key, {
            id: had?.id ?? createStandingId(),
            alliance: had?.alliance ?? x.alliance,
            standing: x.standing,
          });
        });

        next[result.character_eve_id] = [...existing.values()];
      });

      await saveAll(next);

      toast.current?.show({
        severity: 'success',
        summary: 'Standings',
        detail: results.length
          ? results.map(r => `${r.character_name}: ${r.standings.length} from ${r.sources.join(' and ')}`).join('; ')
          : 'Those contact lists have no alliance entries.',
        life: 6000,
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
  }, [byCharacter, outCommand, saveAll]);

  return (
    <div className="w-full h-full min-h-0 flex flex-col gap-3 overflow-y-auto custom-scrollbar pr-1">
      <span className="text-stone-400 text-[12px] shrink-0">
        Colours the ticker under null sec systems, as the character you are flying sees it. Ticker or alliance name;
        -10 danger, -5 warning, +5 friendly.
      </span>

      <div className="flex items-center gap-2 shrink-0">
        <label className="text-[var(--gray-200)] text-[13px] select-none">Standings for:</label>
        <Dropdown
          className="text-sm"
          value={selected}
          options={characterOptions}
          onChange={e => setSelected(e.value)}
        />
      </div>

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
        <span className="text-stone-500 text-[12px] shrink-0">
          Nothing set for this character{selected === SHARED_STANDINGS ? '' : ' - it falls back on All characters'}.
        </span>
      )}

      <div className="flex items-center gap-2 shrink-0">
        <WdButton size="small" outlined icon="pi pi-plus" label="Add alliance" onClick={handleAdd} />
        <WdButton
          size="small"
          outlined
          icon="pi pi-cloud-download"
          label="Import from EVE"
          tooltip="Reads the contact lists of your tracked characters"
          disabled={importing}
          onClick={handleImport}
        />
      </div>

      <Toast ref={toast} />
    </div>
  );
};
