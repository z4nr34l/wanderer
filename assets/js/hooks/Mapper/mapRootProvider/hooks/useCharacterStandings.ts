import { useEffect, useMemo, useRef, useState } from 'react';
import { OutCommand, OutCommandHandler } from '@/hooks/Mapper/types';
import { AllianceStanding, parseAllianceStandings } from '@/hooks/Mapper/constants/standings.ts';

/**
 * The standings of the character being flown, read from EVE rather than kept in settings.
 *
 * Two characters in different alliances disagree by design, so this follows whoever the map is
 * following and asks again when that changes. Nothing is stored: there is no copy to drift and
 * nothing for two people to set differently.
 */
export const useCharacterStandings = (outCommand: OutCommandHandler, characterEveId?: string | null) => {
  const [standings, setStandings] = useState<AllianceStanding[]>([]);
  const ref = useRef({ outCommand });
  ref.current = { outCommand };

  useEffect(() => {
    if (!characterEveId) {
      setStandings([]);
      return;
    }

    let current = true;

    const load = async () => {
      try {
        const res = await ref.current.outCommand<{ standings?: unknown }>({
          type: OutCommand.getCharacterStandings,
          data: { character_eve_id: characterEveId },
        });

        // a character switch while this was in flight would otherwise land on the wrong one
        if (current) {
          setStandings(parseAllianceStandings(res?.standings));
        }
      } catch {
        if (current) {
          setStandings([]);
        }
      }
    };

    load();

    return () => {
      current = false;
    };
  }, [characterEveId]);

  return useMemo(() => ({ standings }), [standings]);
};
