import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { useCallback, useMemo, useRef, useState } from 'react';
import { Toast } from 'primereact/toast';
import { parseMapUserSettings } from '@/hooks/Mapper/components/helpers';
import { saveTextFile } from '@/hooks/Mapper/utils/saveToFile.ts';
import { SplitButton } from 'primereact/splitbutton';
import { loadTextFile } from '@/hooks/Mapper/utils';
import { applyMigrations } from '@/hooks/Mapper/mapRootProvider/migrations';
import { createDefaultStoredSettings } from '@/hooks/Mapper/mapRootProvider/helpers/createDefaultStoredSettings.ts';
import { OutCommand } from '@/hooks/Mapper/types';
import { WdButton } from '@/hooks/Mapper/components/ui-kit';
import { Dialog } from 'primereact/dialog';
import { WdCheckbox } from '@/hooks/Mapper/components/ui-kit/WdCheckbox';

type MapSource = {
  baseUrl: string;
  slug: string;
  token: string;
};

type PendingImport = {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  document: any;
  systems: number;
  connections: number;
  signatures: number;
  hiddenSystems: number;
  // where it came from, which is what the confirmation has to say out loud
  from: string;
  source: MapSource | null;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const countOf = (document: any, key: string) => (Array.isArray(document?.[key]) ? document[key].length : 0);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const describe = (document: any, from: string, source: MapSource | null): PendingImport => ({
  document,
  from,
  source,
  systems: countOf(document, 'systems'),
  connections: countOf(document, 'connections'),
  signatures: countOf(document, 'signatures'),
  hiddenSystems: Array.isArray(document?.systems)
    ? document.systems.filter((system: { visible?: boolean }) => system?.visible === false).length
    : 0,
});

export const ImportExport = () => {
  const {
    storedSettings: { getSettingsForExport, applySettings },
    data: { map_slug },
    outCommand,
  } = useMapRootState();

  const toast = useRef<Toast | null>(null);
  const [mapDataBusy, setMapDataBusy] = useState(false);
  const [includeSignatures, setIncludeSignatures] = useState(true);
  const [pendingImport, setPendingImport] = useState<PendingImport | null>(null);
  const [source, setSource] = useState<MapSource>({ baseUrl: '', slug: '', token: '' });

  const handleImportFromClipboard = useCallback(async () => {
    const text = await navigator.clipboard.readText();

    if (text == null || text == '') {
      return;
    }

    try {
      // INFO: WE NOT SUPPORT MIGRATIONS FOR OLD FILES AND Clipboard
      const parsed = parseMapUserSettings(text);
      if (applySettings(applyMigrations(parsed) || createDefaultStoredSettings())) {
        toast.current?.show({
          severity: 'success',
          summary: 'Import',
          detail: 'Map settings was imported successfully.',
          life: 3000,
        });

        setTimeout(() => {
          window.dispatchEvent(new Event('resize'));
        }, 100);
        return;
      }

      toast.current?.show({
        severity: 'warn',
        summary: 'Warning',
        detail: 'Settings already imported. Or something went wrong.',
        life: 3000,
      });
    } catch (error) {
      console.error(`Import from clipboard Error: `, error);

      toast.current?.show({
        severity: 'error',
        summary: 'Error',
        detail: 'Some error occurred on import from Clipboard, check console log.',
        life: 3000,
      });
    }
  }, [applySettings]);

  const handleImportFromFile = useCallback(async () => {
    try {
      const text = await loadTextFile();

      // INFO: WE NOT SUPPORT MIGRATIONS FOR OLD FILES AND Clipboard
      const parsed = parseMapUserSettings(text);
      if (applySettings(applyMigrations(parsed) || createDefaultStoredSettings())) {
        toast.current?.show({
          severity: 'success',
          summary: 'Import',
          detail: 'Map settings was imported successfully.',
          life: 3000,
        });
        return;
      }

      toast.current?.show({
        severity: 'warn',
        summary: 'Warning',
        detail: 'Settings already imported. Or something went wrong.',
        life: 3000,
      });
    } catch (error) {
      console.error(`Import from file Error: `, error);

      toast.current?.show({
        severity: 'error',
        summary: 'Error',
        detail: 'Some error occurred on import from File, check console log.',
        life: 3000,
      });
    }
  }, [applySettings]);

  const handleExportToClipboard = useCallback(async () => {
    const settings = getSettingsForExport();
    if (!settings) {
      return;
    }

    try {
      await navigator.clipboard.writeText(settings);
      toast.current?.show({
        severity: 'success',
        summary: 'Export',
        detail: 'Map settings copied into clipboard',
        life: 3000,
      });
    } catch (error) {
      console.error(`Export to clipboard Error: `, error);
      toast.current?.show({
        severity: 'error',
        summary: 'Error',
        detail: 'Some error occurred on copying to clipboard, check console log.',
        life: 3000,
      });
    }
  }, [getSettingsForExport]);

  const handleExportToFile = useCallback(async () => {
    const settings = getSettingsForExport();
    if (!settings) {
      return;
    }

    try {
      saveTextFile(`map_settings_${map_slug}.json`, settings);

      toast.current?.show({
        severity: 'success',
        summary: 'Export to File',
        detail: 'Map settings successfully saved to file',
        life: 3000,
      });
    } catch (error) {
      console.error(`Export to cliboard Error: `, error);
      toast.current?.show({
        severity: 'error',
        summary: 'Error',
        detail: 'Some error occurred on saving to file, check console log.',
        life: 3000,
      });
    }
  }, [getSettingsForExport, map_slug]);

  const handleExportMapData = useCallback(async () => {
    setMapDataBusy(true);

    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const res: any = await outCommand({
        type: OutCommand.exportMapData,
        data: { include_signatures: includeSignatures },
      });

      if (!res?.data) {
        throw new Error(res?.error ?? 'Empty response');
      }

      const { systems = [], connections = [], signatures = [] } = res.data;

      saveTextFile(`map_${map_slug}_${new Date().toISOString().slice(0, 10)}.json`, JSON.stringify(res.data, null, 2));

      toast.current?.show({
        severity: 'success',
        summary: 'Export map',
        detail: `Saved ${systems.length} systems, ${connections.length} connections, ${signatures.length} signatures.`,
        life: 4000,
      });
    } catch (error) {
      console.error('Export map data Error: ', error);

      toast.current?.show({
        severity: 'error',
        summary: 'Error',
        detail: 'Some error occurred on exporting map data, check console log.',
        life: 3000,
      });
    } finally {
      setMapDataBusy(false);
    }
  }, [includeSignatures, outCommand, map_slug]);

  const handleImportMapData = useCallback(async () => {
    let parsed;

    try {
      parsed = JSON.parse(await loadTextFile());
    } catch (error) {
      console.error('Import map data Error: ', error);

      toast.current?.show({
        severity: 'error',
        summary: 'Error',
        detail: 'Selected file is not a valid map export.',
        life: 3000,
      });
      return;
    }

    // the map is shared and an import cannot be undone, so the counts get confirmed first
    setPendingImport(describe(parsed, 'that file', null));
  }, []);

  // Reading another map directly: the same import, only the document is fetched with that map's
  // own API key instead of being carried around as a file.
  const handleReadMap = useCallback(async () => {
    if (source.slug.trim() === '' || source.token.trim() === '') {
      toast.current?.show({
        severity: 'warn',
        summary: 'Import map',
        detail: 'A map slug and its API key are needed.',
        life: 3000,
      });
      return;
    }

    setMapDataBusy(true);

    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const res: any = await outCommand({
        type: OutCommand.previewMapData,
        data: { base_url: source.baseUrl, slug: source.slug, token: source.token },
      });

      if (!res?.document) {
        throw new Error(res?.error ?? 'Empty response');
      }

      setPendingImport(describe(res.document, source.baseUrl.trim() === '' ? source.slug : source.baseUrl, source));
    } catch (error) {
      console.error('Read map Error: ', error);

      toast.current?.show({
        severity: 'error',
        summary: 'Error',
        detail: error instanceof Error ? error.message : 'Could not read that map.',
        life: 4000,
      });
    } finally {
      setMapDataBusy(false);
    }
  }, [outCommand, source]);

  const handleConfirmImport = useCallback(async () => {
    if (!pendingImport) {
      return;
    }

    const { document, source: from } = pendingImport;

    setPendingImport(null);
    setMapDataBusy(true);

    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const res: any = await outCommand(
        from
          ? {
              type: OutCommand.pullMapData,
              data: {
                base_url: from.baseUrl,
                slug: from.slug,
                token: from.token,
                include_signatures: includeSignatures,
              },
            }
          : { type: OutCommand.importMapData, data: { data: document, include_signatures: includeSignatures } },
      );

      if (!res?.result) {
        throw new Error(res?.error ?? 'Empty response');
      }

      const { systems, connections, signatures, hidden_systems = 0, comments = 0, structures = 0 } = res.result;

      toast.current?.show({
        severity: 'success',
        summary: 'Import map',
        detail:
          systems + connections + signatures + hidden_systems + comments + structures === 0
            ? 'Everything in that map was already on this one - nothing was added.'
            : [
                `Added ${systems} systems, ${connections} connections, ${signatures} signatures`,
                hidden_systems > 0 ? `${hidden_systems} systems off the map` : null,
                comments > 0 ? `${comments} comments` : null,
                structures > 0 ? `${structures} structures` : null,
              ]
                .filter(Boolean)
                .join(', ') + '.',
        life: 4000,
      });
    } catch (error) {
      console.error('Import map data Error: ', error);

      toast.current?.show({
        severity: 'error',
        summary: 'Error',
        detail: error instanceof Error ? error.message : 'Some error occurred on importing map data.',
        life: 4000,
      });
    } finally {
      setMapDataBusy(false);
    }
  }, [includeSignatures, outCommand, pendingImport]);

  const importItems = useMemo(
    () => [
      {
        label: 'Import from File',
        icon: 'pi pi-file-import',
        command: handleImportFromFile,
      },
    ],
    [handleImportFromFile],
  );

  const exportItems = useMemo(
    () => [
      {
        label: 'Export as File',
        icon: 'pi pi-file-export',
        command: handleExportToFile,
      },
    ],
    [handleExportToFile],
  );

  return (
    <div className="w-full h-full flex flex-col gap-5 overflow-y-auto pr-1">
      <div className="flex flex-col gap-1">
        <div>
          <SplitButton
            onClick={handleImportFromClipboard}
            icon="pi pi-download"
            size="small"
            severity="warning"
            label="Import from Clipboard"
            className="py-[4px]"
            model={importItems}
          />
        </div>

        <span className="text-stone-500 text-[12px]">
          *Will read map settings from clipboard. Be careful it could overwrite current settings.
        </span>
      </div>

      <div className="flex flex-col gap-1">
        <div>
          <SplitButton
            onClick={handleExportToClipboard}
            icon="pi pi-upload"
            size="small"
            label="Export to Clipboard"
            className="py-[4px]"
            model={exportItems}
          />
        </div>

        <span className="text-stone-500 text-[12px]">*Will save map settings to clipboard.</span>
      </div>

      <div className="border-b-2 border-dotted border-stone-700/50 h-px" />

      <div className="flex flex-col gap-2">
        <span className="text-stone-200 text-[13px] font-semibold">Import a map</span>

        <span className="text-stone-500 text-[12px]">
          Reads another map where it lives, with the API key that map hands out. Systems - including the ones taken off
          the map, notes and all - connections, signatures, comments and structures. What is already here is left alone.
        </span>

        <input
          type="text"
          value={source.baseUrl}
          placeholder="Instance address, e.g. wanderer.ltd (empty for this one)"
          onChange={e => setSource(current => ({ ...current, baseUrl: e.target.value }))}
          className="w-full bg-stone-900 border border-stone-700 rounded px-2 py-1 text-[12px]"
        />

        <div className="flex gap-2">
          <input
            type="text"
            value={source.slug}
            placeholder="Map slug"
            onChange={e => setSource(current => ({ ...current, slug: e.target.value }))}
            className="w-1/3 bg-stone-900 border border-stone-700 rounded px-2 py-1 text-[12px]"
          />
          <input
            type="password"
            value={source.token}
            placeholder="That map's API key"
            onChange={e => setSource(current => ({ ...current, token: e.target.value }))}
            className="flex-1 bg-stone-900 border border-stone-700 rounded px-2 py-1 text-[12px] font-mono"
          />
        </div>

        <WdCheckbox
          label="Include signatures"
          value={includeSignatures}
          onChange={e => setIncludeSignatures(!!e.checked)}
        />

        <div className="flex gap-2 items-center">
          <WdButton
            onClick={handleReadMap}
            icon="pi pi-cloud-download"
            size="small"
            severity="warning"
            label="Read that map"
            className="py-[4px]"
            disabled={mapDataBusy}
          />

          <WdButton
            onClick={handleExportMapData}
            icon="pi pi-file-export"
            size="small"
            outlined
            label="Save this map to a file"
            className="py-[4px]"
            disabled={mapDataBusy}
          />
        </div>

        <button
          type="button"
          onClick={handleImportMapData}
          disabled={mapDataBusy}
          className="self-start text-stone-500 hover:text-stone-300 text-[12px] underline"
        >
          or import from a file somebody sent you
        </button>
      </div>

      <Dialog
        header="Import map"
        visible={pendingImport != null}
        draggable={false}
        className="w-[420px]"
        onHide={() => setPendingImport(null)}
      >
        <div className="flex flex-col gap-3">
          <span className="text-stone-200 text-[13px]">
            From <b>{pendingImport?.from}</b>: up to {pendingImport?.systems} systems, {pendingImport?.connections}{' '}
            connections and {includeSignatures ? pendingImport?.signatures : 0} signatures go onto{' '}
            <b>{map_slug ?? 'this map'}</b>, for everyone on the map. Systems already there are left alone, and an
            import cannot be undone.
            {(pendingImport?.hiddenSystems ?? 0) > 0 &&
              ` ${pendingImport?.hiddenSystems} of those systems are off the map over there; they arrive off the map
                here too, carrying whatever was written about them.`}
          </span>

          <div className="flex justify-end gap-2">
            <WdButton size="small" outlined label="Cancel" onClick={() => setPendingImport(null)} />
            <WdButton size="small" severity="warning" label="Import" onClick={handleConfirmImport} />
          </div>
        </div>
      </Dialog>

      <Toast ref={toast} />
    </div>
  );
};
