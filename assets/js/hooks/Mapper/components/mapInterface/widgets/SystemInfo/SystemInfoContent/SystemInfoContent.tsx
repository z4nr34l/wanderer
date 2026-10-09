import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { isWormholeSpace } from '@/hooks/Mapper/components/map/helpers/isWormholeSpace.ts';
import { useMemo } from 'react';
import { getSystemById, sortWHClasses } from '@/hooks/Mapper/helpers';
import { InfoDrawer, MarkdownTextViewer, WHClassView, WHEffectView } from '@/hooks/Mapper/components/ui-kit';
import { useWhoFliesHere } from '@/hooks/Mapper/hooks/useWhoFliesHere.ts';
import { useNpcKills } from '@/hooks/Mapper/hooks/useNpcKills.ts';
import { getSystemStaticInfo } from '@/hooks/Mapper/mapRootProvider/hooks/useLoadSystemStatic';

interface SystemInfoContentProps {
  systemId: string;
  onEditClick?(): void;
}
export const SystemInfoContent = ({ systemId }: SystemInfoContentProps) => {
  const {
    data: { systems, wormholesData },
  } = useMapRootState();

  const sys = getSystemById(systems, systemId)! || {};
  const systemStaticInfo = getSystemStaticInfo(systemId)!;
  const { description } = sys;
  const {
    system_class,
    region_name,
    constellation_name,
    statics,
    effect_name,
    effect_power,
    sovereignty,
    region_sovereignty,
  } = systemStaticInfo || {};
  const isWH = isWormholeSpace(system_class);
  const sortedStatics = useMemo(() => sortWHClasses(wormholesData, statics), [wormholesData, statics]);

  // out in null sec the neighbours are whoever holds the sovereignty; in a hole there is no such
  // thing, so the killboard is the only thing that can answer who has been through lately
  const { whoFliesHere, loading: whoLoading } = useWhoFliesHere(isWH ? systemId : undefined);
  const npcKills = useNpcKills(systemId);

  return (
    <div className="flex flex-col gap-1 p-2">
      <InfoDrawer title="Constellation & Region">
        {constellation_name} / {region_name}
      </InfoDrawer>

      {sovereignty?.alliance_name && (
        <InfoDrawer title="Sovereignty">
          <span className="text-purple-300">{sovereignty.alliance_ticker}</span> {sovereignty.alliance_name}
        </InfoDrawer>
      )}

      {/* a system nobody holds still sits in somebody's part of space */}
      {!sovereignty?.alliance_name && region_sovereignty && (
        <InfoDrawer title="Region held by">
          <span className="text-purple-300">{region_sovereignty.alliance_ticker}</span>{' '}
          {region_sovereignty.alliance_name}{' '}
          <span className="text-stone-500">
            ({region_sovereignty.held}/{region_sovereignty.total})
          </span>
        </InfoDrawer>
      )}

      {/* whether anybody is ratting here, which says whether the space is lived in at all */}
      {npcKills && (
        <InfoDrawer title="NPC kills">
          <span className="text-stone-300">{npcKills.last_hour}</span>
          <span className="text-stone-500"> last hour</span>
          <span className="text-stone-600"> &middot; </span>
          <span className="text-stone-300">{npcKills.last_day}</span>
          <span className="text-stone-500">{npcKills.hours >= 24 ? ' last 24h' : ` last ${npcKills.hours}h`}</span>
        </InfoDrawer>
      )}

      {isWH && (
        <InfoDrawer title="Statics">
          <div className="flex gap-1">
            {sortedStatics.map(x => (
              <WHClassView key={x} whClassName={x} />
            ))}
          </div>
        </InfoDrawer>
      )}

      {/* out in null sec the neighbours are the sovereignty holder; in a hole there is no such
          thing, so who has been shooting in it over the last day is the only answer */}
      {isWH && (whoLoading || whoFliesHere) && (
        <InfoDrawer title="Seen here (24h)">
          {whoLoading && <span className="text-stone-500">Reading the killboard...</span>}

          {!whoLoading &&
            whoFliesHere &&
            whoFliesHere.alliances.length === 0 &&
            whoFliesHere.corporations.length === 0 && <span className="text-stone-500">Nothing in the last day.</span>}

          {!whoLoading && whoFliesHere && (
            <div className="flex flex-col gap-[2px]">
              {(whoFliesHere.alliances.length ? whoFliesHere.alliances : whoFliesHere.corporations).map(group => (
                <div key={group.id} className="flex justify-between gap-2">
                  <span className="text-stone-300 truncate">
                    {group.ticker ? <span className="text-purple-300">[{group.ticker}] </span> : null}
                    {group.name}
                  </span>
                  <span className="text-stone-500 shrink-0">{group.kills}</span>
                </div>
              ))}
            </div>
          )}
        </InfoDrawer>
      )}

      {isWH && effect_name && (
        <InfoDrawer title="Effect">
          <WHEffectView effectName={effect_name} effectPower={effect_power} />
        </InfoDrawer>
      )}

      {description && (
        <InfoDrawer
          title={
            <div className="flex gap-1 items-center">
              <div>Description</div>
            </div>
          }
        >
          <MarkdownTextViewer>{description}</MarkdownTextViewer>
        </InfoDrawer>
      )}
    </div>
  );
};
