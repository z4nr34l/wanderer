import { Dialog } from 'primereact/dialog';
import { useEffect, useMemo, useState } from 'react';
import ReactFlow, { Background, Edge, Node, ReactFlowProvider } from 'reactflow';
import clsx from 'clsx';
import { HomeNode, HomeWaysIn, KnownHome } from '@/hooks/Mapper/hooks/useKnownHomes.ts';

type HomeWaysInDialogProps = {
  home: KnownHome | null;
  load: (home: KnownHome) => Promise<HomeWaysIn | undefined>;
  onHide: () => void;
};

const CLASS_COLOURS: Record<HomeNode['class'], string> = {
  high: 'border-emerald-400 text-emerald-300',
  low: 'border-amber-400 text-amber-300',
  null: 'border-red-400 text-red-300',
  wormhole: 'border-sky-400 text-sky-300',
};

// the home sits on the right, every hole out of it one step to the left, so a route reads the
// way somebody flies it: in from the edge of the picture
const COLUMN = 150;
const ROW = 64;

const layout = (ways: HomeWaysIn['ways_in']): { nodes: Node[]; edges: Edge[] } => {
  const deepest = Math.max(...ways.nodes.map(node => node.holes), 0);
  const perColumn: Record<number, number> = {};

  const nodes = ways.nodes.map(node => {
    const column = deepest - node.holes;
    const row = perColumn[node.holes] ?? 0;
    perColumn[node.holes] = row + 1;

    return {
      id: `${node.solar_system_id}`,
      position: { x: column * COLUMN, y: row * ROW },
      data: { label: node },
      type: 'homeWay',
      draggable: false,
      connectable: false,
    };
  });

  const edges = ways.edges.map(edge => ({
    id: `${edge.source}_${edge.target}`,
    source: `${edge.source}`,
    target: `${edge.target}`,
    type: 'straight',
    style: { stroke: '#57534e' },
  }));

  return { nodes, edges };
};

const HomeWayNode = ({ data }: { data: { label: HomeNode } }) => {
  const node = data.label;

  return (
    <div
      className={clsx(
        'px-2 py-1 rounded border bg-stone-900/90 text-[11px] whitespace-nowrap',
        CLASS_COLOURS[node.class],
        { 'ring-1 ring-stone-200': node['home?'] },
      )}
    >
      <div className="font-semibold">{node.name}</div>
      <div className="text-stone-500">{node['home?'] ? 'home' : node['mouth?'] ? 'way in' : `${node.holes} in`}</div>
    </div>
  );
};

const nodeTypes = { homeWay: HomeWayNode };

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

  const flow = useMemo(() => (data ? layout(data.ways_in) : { nodes: [], edges: [] }), [data]);

  return (
    <Dialog
      header={home ? `Way into ${home.map_name}` : 'Way in'}
      visible={home != null}
      draggable={false}
      resizable={false}
      style={{ width: '720px' }}
      onHide={onHide}
    >
      {home && (
        <div className="flex flex-col gap-2">
          <div className="text-xs text-stone-400">
            Their chain, cut down to what leads in - every route from a hole in k-space to the home.
          </div>

          {loading && <div className="text-sm text-stone-400">Reading their map...</div>}

          {!loading && flow.nodes.length <= 1 && (
            <div className="text-sm text-stone-400">
              Nothing on their map leads in yet - no k-space system with a hole into the chain.
            </div>
          )}

          {!loading && flow.nodes.length > 1 && (
            <div className="h-[380px] w-full rounded border border-stone-800">
              <ReactFlowProvider>
                <ReactFlow
                  nodes={flow.nodes}
                  edges={flow.edges}
                  nodeTypes={nodeTypes}
                  fitView
                  nodesDraggable={false}
                  nodesConnectable={false}
                  elementsSelectable={false}
                  proOptions={{ hideAttribution: true }}
                >
                  <Background color="#292524" gap={16} />
                </ReactFlow>
              </ReactFlowProvider>
            </div>
          )}
        </div>
      )}
    </Dialog>
  );
};
