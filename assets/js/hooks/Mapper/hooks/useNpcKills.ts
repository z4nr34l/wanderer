import { useEffect, useRef, useState } from 'react';
import { OutCommand } from '@/hooks/Mapper/types';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';

export type NpcKills = {
  last_hour: number;
  last_day: number;
  // how many hours the day actually covers - fewer than 24 only right after this was switched on
  hours: number;
};

/**
 * NPC kills in a system, the way Dotlan counts them: the hour CCP last published, and the day.
 * Asked as somebody looks at a system, since it changes by the hour.
 */
export const useNpcKills = (solarSystemId: string | undefined) => {
  const { outCommand } = useMapRootState();
  const [data, setData] = useState<NpcKills | undefined>();

  const ref = useRef({ outCommand });
  ref.current = { outCommand };

  useEffect(() => {
    if (!solarSystemId) {
      setData(undefined);
      return;
    }

    let current = true;
    setData(undefined);

    ref.current
      .outCommand<{ npc_kills?: NpcKills | null }>({
        type: OutCommand.getNpcKills,
        data: { solar_system_id: solarSystemId },
      })
      .then(res => {
        if (current) {
          setData(res?.npc_kills ?? undefined);
        }
      })
      .catch(() => {
        if (current) {
          setData(undefined);
        }
      });

    return () => {
      current = false;
    };
  }, [solarSystemId]);

  return data;
};
