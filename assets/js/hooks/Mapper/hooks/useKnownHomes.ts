import { useCallback, useEffect, useRef, useState } from 'react';
import { OutCommand, OutCommandHandler } from '@/hooks/Mapper/types';

export type KnownHome = {
  map_id: string;
  map_name: string;
  map_slug: string;
  solar_system_id: number;
};

export type HomeWayIn = {
  solar_system_id: number;
  name: string;
  class: 'high' | 'low' | 'null';
  security: number | null;
  holes: number;
};

export type HomeWaysIn = {
  home: { map_name: string; map_slug: string; solar_system_id: number };
  ways_in: HomeWayIn[];
};

/**
 * The homes other maps have declared, keyed by the system they sit in.
 *
 * Only maps this person may already open come back, so a marker on the chain never says more
 * than they could find by opening those maps themselves.
 */
export const useKnownHomes = (outCommand: OutCommandHandler) => {
  const [homes, setHomes] = useState<Record<string, KnownHome>>({});
  const ref = useRef({ outCommand });
  ref.current = { outCommand };

  useEffect(() => {
    let current = true;

    const load = async () => {
      try {
        const res = await ref.current.outCommand<{ homes?: KnownHome[] }>({
          type: OutCommand.getKnownHomes,
          data: {},
        });

        if (current) {
          setHomes(Object.fromEntries((res?.homes ?? []).map(home => [`${home.solar_system_id}`, home])));
        }
      } catch {
        if (current) {
          setHomes({});
        }
      }
    };

    load();

    return () => {
      current = false;
    };
  }, []);

  const waysIn = useCallback(async (home: KnownHome) => {
    const res = await ref.current.outCommand<HomeWaysIn & { error?: string }>({
      type: OutCommand.getHomeWaysIn,
      data: { map_id: home.map_id, solar_system_id: home.solar_system_id },
    });

    return res?.error ? undefined : res;
  }, []);

  return { homes, waysIn };
};
