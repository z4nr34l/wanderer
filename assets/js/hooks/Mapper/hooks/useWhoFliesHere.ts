import { useEffect, useRef, useState } from 'react';
import { OutCommand } from '@/hooks/Mapper/types';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';

export type FlyingGroup = {
  id: number;
  name: string;
  ticker: string | null;
  kills: number;
};

// who has been seen in a hole over the last two days
export type WhoFliesHere = {
  alliances: FlyingGroup[];
  corporations: FlyingGroup[];
};

/**
 * Who has been seen in a wormhole lately, read from the kills in it.
 *
 * Null sec has sovereignty and a region whose space it is; a hole has neither, and the killboard
 * is the only thing that can say who has been through. Asked one system at a time, as somebody
 * looks at it, because that is the only moment the answer is wanted.
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
