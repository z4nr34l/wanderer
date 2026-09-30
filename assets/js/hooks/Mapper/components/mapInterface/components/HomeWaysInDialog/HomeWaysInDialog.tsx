import { Dialog } from 'primereact/dialog';
import { useEffect, useMemo, useState } from 'react';

import { MapPreview } from '@/hooks/Mapper/components/mapInterface/components/MapPreview';
import { HomeWaysIn, KnownHome } from '@/hooks/Mapper/hooks/useKnownHomes.ts';

import classes from './HomeWaysInDialog.module.scss';

type HomeWaysInDialogProps = {
  home: KnownHome | null;
  load: (home: KnownHome) => Promise<HomeWaysIn | undefined>;
  onHide: () => void;
};

export const HomeWaysInDialog = ({ home, load, onHide }: HomeWaysInDialogProps) => {
  const [data, setData] = useState<HomeWaysIn | undefined>();
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!home) {
      setData(undefined);
      return;
    }

    let current = true;
    setLoading(true);

    load(home)
      .then(result => {
        if (current) {
          setData(result);
        }
      })
      .finally(() => {
        if (current) {
          setLoading(false);
        }
      });

    return () => {
      current = false;
    };
  }, [home, load]);

  const waysIn = data?.ways_in;

  const ringed = useMemo(() => {
    if (!waysIn) {
      return {};
    }

    return Object.fromEntries(
      Object.entries(waysIn.markers).map(([systemId, marker]) => [
        systemId,
        marker.home ? classes.Home : marker.mouth ? classes.WayIn : undefined,
      ]),
    );
  }, [waysIn]);

  const hasChain = (waysIn?.systems?.length ?? 0) > 0;

  return (
    <Dialog
      header={home ? `Way into ${home.map_name}` : 'Way in'}
      visible={home != null}
      draggable={false}
      resizable={false}
      style={{ width: '760px' }}
      onHide={onHide}
    >
      {home && (
        <div className="flex flex-col gap-2">
          <div className="text-xs text-stone-400">
            Their chain, cut down to what leads in - every route from a hole in k-space to the home. The home is ringed
            in white, the ways in are ringed in green. Right-click a system to send your own pilots there, or to plot a
            jump to it.
          </div>

          {loading && <div className="text-sm text-stone-400">Reading their map...</div>}

          {!loading && !hasChain && (
            <div className="text-sm text-stone-400">
              Nothing on their map leads in yet - no k-space system with a hole into the chain.
            </div>
          )}

          {!loading && hasChain && (
            <div className="h-[420px] w-full rounded border border-stone-800">
              <MapPreview
                systems={waysIn!.systems}
                connections={waysIn!.connections}
                ringed={ringed}
                onLeave={onHide}
              />
            </div>
          )}
        </div>
      )}
    </Dialog>
  );
};
