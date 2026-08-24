import { useCallback, useEffect, useRef, useState } from 'react';
import { OutCommand, OutCommandHandler } from '@/hooks/Mapper/types';

export type LiveShipFit = {
  character_eve_id: string;
  ship_type_id: number;
  ship_name: string;
  prop_module?: string | null;
  cold_mass: number;
  hot_mass: number;
};

export type ShipFitRequest = {
  characterEveId: string;
  // what the character is flying - a different ship means the fit has to be read again
  shipKey: string;
};

type ShipFitResponse = { fit?: LiveShipFit; error?: string };

const requestKey = ({ characterEveId, shipKey }: ShipFitRequest) => `${characterEveId}:${shipKey}`;

/**
 * The weighed fit of the ship each of the given characters is flying, straight from EVE.
 *
 * Only characters the user tracks can be read - the server answers with an error for anyone
 * else, and that error is kept so the same question is not asked twice. A character stepping
 * into another ship changes its key, which is what makes the fit be read again.
 */
export const useShipFits = (outCommand: OutCommandHandler, requests: ShipFitRequest[]) => {
  const [fits, setFits] = useState<Record<string, LiveShipFit>>({});
  const [errors, setErrors] = useState<Record<string, string>>({});
  const asked = useRef(new Set<string>());
  const ref = useRef({ outCommand });
  ref.current = { outCommand };

  const load = useCallback(async (request: ShipFitRequest) => {
    const key = requestKey(request);

    try {
      const res = await ref.current.outCommand<ShipFitResponse>({
        type: OutCommand.getShipFit,
        data: { character_eve_id: request.characterEveId },
      });

      if (res?.fit) {
        setFits(prev => ({ ...prev, [key]: res.fit as LiveShipFit }));
        setErrors(prev => (prev[key] ? { ...prev, [key]: '' } : prev));
        return;
      }

      setErrors(prev => ({ ...prev, [key]: res?.error ?? 'unavailable' }));
    } catch {
      setErrors(prev => ({ ...prev, [key]: 'unavailable' }));
    }
  }, []);

  useEffect(() => {
    requests.forEach(request => {
      const key = requestKey(request);

      if (asked.current.has(key)) {
        return;
      }

      asked.current.add(key);
      load(request);
    });
  }, [load, requests]);

  const refresh = useCallback(
    (request: ShipFitRequest) => {
      asked.current.add(requestKey(request));
      return load(request);
    },
    [load],
  );

  const fitFor = useCallback((request: ShipFitRequest) => fits[requestKey(request)], [fits]);

  const errorFor = useCallback((request: ShipFitRequest) => errors[requestKey(request)] || undefined, [errors]);

  return { fitFor, errorFor, refresh };
};
