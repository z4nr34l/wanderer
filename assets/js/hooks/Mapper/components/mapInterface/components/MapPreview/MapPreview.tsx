import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import ReactFlow, { Background, ConnectionMode, ReactFlowProvider } from 'reactflow';
import { ContextMenu } from 'primereact/contextmenu';
import { MenuItem } from 'primereact/menuitem';
import clsx from 'clsx';

import { FastSystemActions } from '@/hooks/Mapper/components/contexts/components';
import { useJumpMenu, useWaypointMenu } from '@/hooks/Mapper/components/contexts/hooks';
import { JumpPlannerField } from '@/hooks/Mapper/components/mapRootContent/components/JumpPlanner';
import { WaypointSetContextHandler } from '@/hooks/Mapper/components/contexts/types.ts';
import { MapProvider, useMapState } from '@/hooks/Mapper/components/map/MapProvider';
import { SolarSystemEdge } from '@/hooks/Mapper/components/map/components/SolarSystemEdge';
import { convertConnection2Edge, convertSystem2Node } from '@/hooks/Mapper/components/map/helpers';
import { getBehaviorForTheme } from '@/hooks/Mapper/components/map/helpers/getThemeBehavior.ts';
import { isWormholeSpace } from '@/hooks/Mapper/components/map/helpers/isWormholeSpace.ts';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { getSystemStaticInfo, useLoadSystemStatic } from '@/hooks/Mapper/mapRootProvider/hooks/useLoadSystemStatic';
import { Commands } from '@/hooks/Mapper/types/mapHandlers.ts';
import { emitMapEvent } from '@/hooks/Mapper/events';
import { OutCommand, SolarSystemConnection, SolarSystemRawType } from '@/hooks/Mapper/types';

export type MapPreviewProps = {
  systems: SolarSystemRawType[];
  connections: SolarSystemConnection[];
  // a class per system, for saying which of them the dialog is about
  ringed?: Record<string, string | undefined>;
  // the jump planner opens on the map behind, so a dialog gets out of the way first
  onLeave?: () => void;
};

const edgeTypes = { floating: SolarSystemEdge };

/**
 * Somebody else's map, drawn the way the map draws itself.
 *
 * The map already knows what a system looks like - its security, its class, its effect, its
 * statics, the colour of its status - so a second renderer here would only be a worse one. What
 * is left to decide is what a right-click may do, and on a map that is not ours that is the two
 * things that change nothing over there: sending our own pilots, and plotting a jump.
 */
const Preview = ({ systems, connections, ringed, onLeave }: MapPreviewProps) => {
  const {
    data: { wormholesData, effects, wormholes },
    outCommand,
  } = useMapRootState();
  const { update } = useMapState();

  const contextMenuRef = useRef<ContextMenu>(null);
  const [menuSystemId, setMenuSystemId] = useState<string | null>(null);

  const solarSystemIds = useMemo(() => systems.map(system => system.id), [systems]);
  const { loading } = useLoadSystemStatic({ systems: solarSystemIds });

  useEffect(() => {
    // the node reads a system's statics and its effect out of the map state it sits in
    update({
      systems,
      connections,
      wormholesData,
      wormholes,
      effects,
      visibleNodes: new Set(solarSystemIds),
    });
  }, [connections, effects, solarSystemIds, systems, update, wormholes, wormholesData]);

  const onWaypointSet: WaypointSetContextHandler = useCallback(
    ({ charIds, clearWay, fromBeginning, destination }) => {
      outCommand({
        type: OutCommand.setAutopilotWaypoint,
        data: {
          character_eve_ids: charIds,
          add_to_beginning: fromBeginning,
          clear_other_waypoints: clearWay,
          destination_id: destination,
        },
      });
      setMenuSystemId(null);
    },
    [outCommand],
  );

  const getWaypointMenu = useWaypointMenu(onWaypointSet);

  const getJumpMenu = useJumpMenu({
    onJumpFrom: systemId => {
      setMenuSystemId(null);
      onLeave?.();
      emitMapEvent({ name: Commands.showJumpPlanner, data: { field: JumpPlannerField.From, systemId } });
    },
    onJumpTo: systemId => {
      setMenuSystemId(null);
      onLeave?.();
      emitMapEvent({ name: Commands.showJumpPlanner, data: { field: JumpPlannerField.Destination, systemId } });
    },
  });

  const menuItems = useMemo((): MenuItem[] => {
    if (!menuSystemId) {
      return [];
    }

    const staticInfo = getSystemStaticInfo(menuSystemId);

    if (!staticInfo) {
      return [];
    }

    return [
      {
        template: () => (
          <FastSystemActions
            systemId={menuSystemId}
            systemName={staticInfo.solar_system_name}
            regionName={staticInfo.region_name}
            isWH={isWormholeSpace(staticInfo.system_class)}
            onOpenSettings={() => {}}
          />
        ),
      },
      { separator: true },
      ...getWaypointMenu(menuSystemId, staticInfo.system_class),
      ...getJumpMenu(menuSystemId, staticInfo.system_class),
    ];
  }, [getJumpMenu, getWaypointMenu, menuSystemId]);

  const { nodeComponent } = getBehaviorForTheme('default');
  const nodeTypes = useMemo(() => ({ custom: nodeComponent }), [nodeComponent]);

  const nodes = useMemo(
    () =>
      systems.map(system => ({
        ...convertSystem2Node(system),
        draggable: false,
        deletable: false,
        connectable: false,
        className: clsx(ringed?.[system.id]),
      })),
    [ringed, systems],
  );

  const edges = useMemo(
    () => connections.map(connection => ({ ...convertConnection2Edge(connection), selectable: false })),
    [connections],
  );

  if (loading) {
    return <div className="text-sm text-stone-400 p-4">Reading their map...</div>;
  }

  return (
    <>
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
        onNodeContextMenu={(event, node) => {
          setMenuSystemId(node.id);
          contextMenuRef.current?.show(event);
        }}
      >
        <Background color="#292524" gap={16} />
      </ReactFlow>

      <ContextMenu className="min-w-[200px]" model={menuItems} ref={contextMenuRef} breakpoint="767px" />
    </>
  );
};

export const MapPreview = (props: MapPreviewProps) => {
  const { outCommand } = useMapRootState();

  return (
    <MapProvider onCommand={outCommand}>
      <ReactFlowProvider>
        <Preview {...props} />
      </ReactFlowProvider>
    </MapProvider>
  );
};
