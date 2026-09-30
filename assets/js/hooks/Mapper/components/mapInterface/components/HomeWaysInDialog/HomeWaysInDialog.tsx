import { Dialog } from 'primereact/dialog';
import { useEffect, useMemo, useState } from 'react';
import ReactFlow, { Background, ConnectionMode, ReactFlowProvider } from 'reactflow';
import clsx from 'clsx';

import { MapProvider, useMapState } from '@/hooks/Mapper/components/map/MapProvider';
import { SolarSystemEdge } from '@/hooks/Mapper/components/map/components/SolarSystemEdge';
import { convertConnection2Edge, convertSystem2Node } from '@/hooks/Mapper/components/map/helpers';
import { getBehaviorForTheme } from '@/hooks/Mapper/components/map/helpers/getThemeBehavior.ts';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { useLoadSystemStatic } from '@/hooks/Mapper/mapRootProvider/hooks/useLoadSystemStatic';
import { HomeWaysIn, KnownHome } from '@/hooks/Mapper/hooks/useKnownHomes.ts';

import classes from './HomeWaysInDialog.module.scss';

type HomeWaysInDialogProps = {
  home: KnownHome | null;
  load: (home: KnownHome) => Promise<HomeWaysIn | undefined>;
  onHide: () => void;
};

const edgeTypes = { floating: SolarSystemEdge };

// Their chain is drawn with the map's own renderer, so a system looks here exactly as it looks on
// the map it came from. The only thing added on top is which of them are the way in.
const WaysIn = ({ waysIn }: { waysIn: HomeWaysIn['ways_in'] }) => {
  const {
    data: { wormholesData, effects, wormholes },
  } = useMapRootState();
  const { update } = useMapState();

  const solarSystemIds = useMemo(() => waysIn.systems.map(system => system.id), [waysIn.systems]);
  const { loading } = useLoadSystemStatic({ systems: solarSystemIds });

  useEffect(() => {
    // the node reads a system's statics and its effect out of the map state it sits in
    update({
      systems: waysIn.systems,
      connections: waysIn.connections,
      wormholesData,
      wormholes,
      effects,
      visibleNodes: new Set(solarSystemIds),
    });
  }, [effects, solarSystemIds, update, waysIn, wormholes, wormholesData]);

  const { nodeComponent } = getBehaviorForTheme('default');
  const nodeTypes = useMemo(() => ({ custom: nodeComponent }), [nodeComponent]);

  const nodes = useMemo(
    () =>
      waysIn.systems.map(system => {
        const marker = waysIn.markers[system.id];

        return {
          ...convertSystem2Node(system),
          draggable: false,
          deletable: false,
          connectable: false,
          className: clsx({
            [classes.Home]: marker?.home,
            [classes.WayIn]: marker?.mouth && !marker?.home,
          }),
        };
      }),
    [waysIn],
  );

  const edges = useMemo(
    () => waysIn.connections.map(connection => ({ ...convertConnection2Edge(connection), selectable: false })),
    [waysIn],
  );

  if (loading) {
    return <div className="text-sm text-stone-400 p-4">Reading their map...</div>;
  }

  return (
    <ReactFlow
      nodes={nodes}
      edges={edges}
      nodeTypes={nodeTypes}
      edgeTypes={edgeTypes}
      connectionMode={ConnectionMode.Loose}
      fitView
      fitViewOptions={{ padding: 0.2 }}
      nodesDraggable={false}
      nodesConnectable={false}
      elementsSelectable={false}
      proOptions={{ hideAttribution: true }}
    >
      <Background color="#292524" gap={16} />
    </ReactFlow>
  );
};

export const HomeWaysInDialog = ({ home, load, onHide }: HomeWaysInDialogProps) => {
  const { outCommand } = useMapRootState();
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

  const hasChain = (data?.ways_in?.systems?.length ?? 0) > 0;

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
            in white, the ways in are ringed in green.
          </div>

          {loading && <div className="text-sm text-stone-400">Reading their map...</div>}

          {!loading && !hasChain && (
            <div className="text-sm text-stone-400">
              Nothing on their map leads in yet - no k-space system with a hole into the chain.
            </div>
          )}

          {!loading && hasChain && (
            <div className="h-[420px] w-full rounded border border-stone-800">
              <MapProvider onCommand={outCommand}>
                <ReactFlowProvider>
                  <WaysIn waysIn={data!.ways_in} />
                </ReactFlowProvider>
              </MapProvider>
            </div>
          )}
        </div>
      )}
    </Dialog>
  );
};
