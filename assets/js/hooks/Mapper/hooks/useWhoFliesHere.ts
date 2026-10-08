import { useEffect, useRef, useState } from 'react';
import { OutCommand } from '@/hooks/Mapper/types';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';

export type FlyingGroup = {
  id: number;
  name: string;
  ticker: string | null;
  kills: number;
};

export type WhoFliesHere = {
  // which question was answered: what is happening now, or who has ever flown here
  window: 'recent' | 'all_time';
  alliances: FlyingGroup[];
  corporations: FlyingGroup[];
};

/**
 * Who a pilot will meet in a system, read from the kills in it.
 *
 * Sovereignty says who owns null sec and the faction on the map says which rats live there;
 * neither says who is actually around. Asked one system at a time, as the person looks at it,
 * because that is the only moment the answer is wanted.
 */
export const useWhoFliesHere = (solarSystemId: string | undefined) => {
  const { outCommand } = useMapRootState();
  const [data, setData] = useState<WhoFliesHere | undefined>();
  const [loading, setLoading] = useState(false);

  const ref = useRef({ outCommand });
  ref.current = { outCommand };

  useEffect(() => {
    if (!solarSystemId) {
      setData(undefined);
      return;
    }

    let current = true;
    setData(undefined);
    setLoading(true);

    ref.current
      .outCommand<{ stats?: WhoFliesHere; error?: string }>({
        type: OutCommand.getWhoFliesHere,
        data: { solar_system_id: solarSystemId },
      })
      .then(res => {
        if (current) {
          setData(res?.stats);
        }
      })
      .catch(() => {
        if (current) {
          setData(undefined);
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
  }, [solarSystemId]);

  return { whoFliesHere: data, loading };
};
