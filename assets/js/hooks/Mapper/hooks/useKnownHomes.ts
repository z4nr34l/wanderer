import { useCallback, useEffect, useRef, useState } from 'react';
import { OutCommand, OutCommandHandler, SolarSystemConnection, SolarSystemRawType } from '@/hooks/Mapper/types';

export type KnownHome = {
  map_id?: string;
  share_id?: string;
  map_name: string;
  map_slug: string;
  solar_system_id: number;
  'remote?'?: boolean;
};

export type HomeMarker = { holes: number; home: boolean; mouth: boolean };

export type LinkedMap = {
  link_id: string;
  map_id: string | null;
  share_id: string | null;
  map_name: string;
  map_slug: string | null;
  'remote?': boolean;
};

export type LinkedMapContents = {
  systems: SolarSystemRawType[];
  connections: SolarSystemConnection[];
};

// how often the overlaps are asked for again: a chain being scanned grows under the reader, and
// a system that has just been added is exactly the one worth knowing about
const REFRESH_MS = 60_000;

export type HomeWaysIn = {
  home: { map_name: string; map_slug: string; solar_system_id: number };
  // the same shape the map is given for its own systems, so it can be drawn with the map's
  // renderer rather than one written for this dialog
  ways_in: {
    systems: SolarSystemRawType[];
    connections: SolarSystemConnection[];
    markers: Record<string, HomeMarker>;
  };
};

/**
 * The homes other maps have declared, keyed by the system they sit in.
 *
 * Only maps this person may already open come back, so a marker on the chain never says more
 * than they could find by opening those maps themselves.
 */
export const useKnownHomes = (outCommand: OutCommandHandler, ready: boolean) => {
  const [homes, setHomes] = useState<Record<string, KnownHome>>({});
  const [links, setLinks] = useState<Record<string, LinkedMap>>({});
  const [overlaps, setOverlaps] = useState<Record<string, string[]>>({});
  const ref = useRef({ outCommand });
  ref.current = { outCommand };

  useEffect(() => {
    if (!ready) {
      return;
    }

    let current = true;

    const load = async () => {
      try {
        const res = await ref.current.outCommand<{
          homes?: KnownHome[];
          links?: LinkedMap[];
          overlaps?: Record<string, string[]>;
        }>({
          type: OutCommand.getKnownHomes,
          data: {},
        });

        if (current) {
          setHomes(Object.fromEntries((res?.homes ?? []).map(home => [`${home.solar_system_id}`, home])));
          setLinks(Object.fromEntries((res?.links ?? []).map(link => [link.link_id, link])));
          setOverlaps(res?.overlaps ?? {});
        }
      } catch {
        if (current) {
          setHomes({});
          setLinks({});
          setOverlaps({});
        }
      }
    };

    load();
    const timer = setInterval(load, REFRESH_MS);

    return () => {
      current = false;
      clearInterval(timer);
    };
  }, [ready]);

  const waysIn = useCallback(async (home: KnownHome) => {
    const res = await ref.current.outCommand<HomeWaysIn & { error?: string }>({
      type: OutCommand.getHomeWaysIn,
      data: home.share_id
        ? { share_id: home.share_id }
        : { map_id: home.map_id, solar_system_id: home.solar_system_id },
    });

    return res?.error ? undefined : res;
  }, []);

  const linkedMap = useCallback(async (link: LinkedMap) => {
    const res = await ref.current.outCommand<{ map?: LinkedMapContents; error?: string }>({
      type: OutCommand.getLinkedMap,
      data: { link_id: link.link_id },
    });

    return res?.error ? undefined : res?.map;
  }, []);

  // which other maps also hold a given system, as the context menu asks it
  const linksFor = useCallback(
    (solarSystemId: string): LinkedMap[] =>
      (overlaps[solarSystemId] ?? []).map(linkId => links[linkId]).filter(Boolean),
    [links, overlaps],
  );

  return { homes, waysIn, linksFor, linkedMap };
};
