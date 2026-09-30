import { Dialog } from 'primereact/dialog';
import { useEffect, useState } from 'react';

import { MapPreview } from '@/hooks/Mapper/components/mapInterface/components/MapPreview';
import { LinkedMap, LinkedMapContents } from '@/hooks/Mapper/hooks/useKnownHomes.ts';

type LinkedMapDialogProps = {
  link: LinkedMap | null;
  // the system both maps hold, which is why this is being read at all
  meetingAt?: string;
  load: (link: LinkedMap) => Promise<LinkedMapContents | undefined>;
  onHide: () => void;
};

export const LinkedMapDialog = ({ link, meetingAt, load, onHide }: LinkedMapDialogProps) => {
  const [data, setData] = useState<LinkedMapContents | undefined>();
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!link) {
      setData(undefined);
      return;
    }

    let current = true;
    setLoading(true);

    load(link)
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
  }, [link, load]);

  const hasMap = (data?.systems?.length ?? 0) > 0;
  const ringed = meetingAt ? { [meetingAt]: 'ring-1 ring-amber-400 rounded' } : undefined;

  return (
    <Dialog
      header={link ? link.map_name : 'Linked map'}
      visible={link != null}
      draggable={false}
      resizable={false}
      style={{ width: '860px' }}
      onHide={onHide}
    >
      {link && (
        <div className="flex flex-col gap-2">
          <div className="text-xs text-stone-400">
            Their map as it stands{link['remote?'] ? ', read from their instance' : ''}. The system both chains hold is
            ringed in amber. Right-click a system to send your own pilots there, or to plot a jump to it - nothing here
            changes their map.
          </div>

          {loading && <div className="text-sm text-stone-400">Reading their map...</div>}

          {!loading && !hasMap && <div className="text-sm text-stone-400">Nothing came back from that map.</div>}

          {!loading && hasMap && (
            <div className="h-[520px] w-full rounded border border-stone-800">
              <MapPreview systems={data!.systems} connections={data!.connections} ringed={ringed} onLeave={onHide} />
            </div>
          )}
        </div>
      )}
    </Dialog>
  );
};
