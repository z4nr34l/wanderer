import { Dialog } from 'primereact/dialog';
import { useEffect, useMemo, useState } from 'react';
import clsx from 'clsx';
import { HomeWayIn, HomeWaysIn, KnownHome } from '@/hooks/Mapper/hooks/useKnownHomes.ts';

type HomeWaysInDialogProps = {
  home: KnownHome | null;
  load: (home: KnownHome) => Promise<HomeWaysIn | undefined>;
  onHide: () => void;
};

const GROUPS: { key: HomeWayIn['class']; label: string; className: string }[] = [
  { key: 'high', label: 'High sec', className: 'text-emerald-400' },
  { key: 'low', label: 'Low sec', className: 'text-amber-400' },
  { key: 'null', label: 'Null sec', className: 'text-red-400' },
];

const holes = (count: number) => (count === 1 ? '1 hole' : `${count} holes`);

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

  const grouped = useMemo(() => {
    const ways = data?.ways_in ?? [];

    return GROUPS.map(group => ({ ...group, ways: ways.filter(way => way.class === group.key) })).filter(
      group => group.ways.length > 0,
    );
  }, [data]);

  return (
    <Dialog
      header={home ? `Ways into ${home.map_name}` : 'Ways in'}
      visible={home != null}
      draggable={false}
      resizable={false}
      style={{ width: '420px' }}
      onHide={onHide}
    >
      {home && (
        <div className="flex flex-col gap-3">
          <div className="text-xs text-stone-400">
            Mouths of that chain, as its own map has them drawn - nearest to the home first.
          </div>

          {loading && <div className="text-sm text-stone-400">Reading their map...</div>}

          {!loading && grouped.length === 0 && (
            <div className="text-sm text-stone-400">
              Nothing on their map leads in yet - no k-space system with a hole into the chain.
            </div>
          )}

          {grouped.map(group => (
            <div key={group.key} className="flex flex-col gap-1">
              <div className={clsx('text-[11px] uppercase tracking-wide', group.className)}>{group.label}</div>

              {group.ways.map(way => (
                <div key={way.solar_system_id} className="grid grid-cols-[1fr_auto] text-[13px]">
                  <span className="text-stone-200">{way.name}</span>
                  <span className="text-stone-500">{holes(way.holes)} to home</span>
                </div>
              ))}
            </div>
          ))}
        </div>
      )}
    </Dialog>
  );
};
