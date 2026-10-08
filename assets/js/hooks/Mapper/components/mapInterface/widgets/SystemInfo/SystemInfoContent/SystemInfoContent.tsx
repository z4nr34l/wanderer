import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { isWormholeSpace } from '@/hooks/Mapper/components/map/helpers/isWormholeSpace.ts';
import { useMemo } from 'react';
import { getSystemById, sortWHClasses } from '@/hooks/Mapper/helpers';
import { InfoDrawer, MarkdownTextViewer, WHClassView, WHEffectView } from '@/hooks/Mapper/components/ui-kit';
import { useWhoFliesHere } from '@/hooks/Mapper/hooks/useWhoFliesHere.ts';
import { getSystemStaticInfo } from '@/hooks/Mapper/mapRootProvider/hooks/useLoadSystemStatic';

interface SystemInfoContentProps {
  systemId: string;
  onEditClick?(): void;
}
export const SystemInfoContent = ({ systemId }: SystemInfoContentProps) => {
  const { whoFliesHere, loading: whoLoading } = useWhoFliesHere(systemId);
  const {
    data: { systems, wormholesData },
  } = useMapRootState();

  const sys = getSystemById(systems, systemId)! || {};
  const systemStaticInfo = getSystemStaticInfo(systemId)!;
  const { description } = sys;
  const { system_class, region_name, constellation_name, statics, effect_name, effect_power, sovereignty } =
    systemStaticInfo || {};
  const isWH = isWormholeSpace(system_class);
  const sortedStatics = useMemo(() => sortWHClasses(wormholesData, statics), [wormholesData, statics]);

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

      {sovereignty?.faction_name && !sovereignty?.alliance_name && (
        <InfoDrawer title="Sovereignty">
          <span className="text-stone-400 italic">{sovereignty.faction_name}</span>
        </InfoDrawer>
      )}

      {/* who owns the space and who is in it are different questions; this is the second */}
      {(whoLoading || whoFliesHere) && (
        <InfoDrawer
          title={whoFliesHere?.window === 'all_time' ? 'Who flies here (all time)' : 'Who flies here (recently)'}
        >
          {whoLoading && <span className="text-stone-500">Reading the killboard...</span>}

          {!whoLoading && whoFliesHere && (
            <div className="flex flex-col gap-[2px]">
              {whoFliesHere.alliances.map(group => (
                <div key={`a-${group.id}`} className="flex justify-between gap-2">
                  <span className="text-stone-300 truncate">
                    {group.ticker ? <span className="text-purple-300">[{group.ticker}] </span> : null}
                    {group.name}
                  </span>
                  <span className="text-stone-500 shrink-0">{group.kills}</span>
                </div>
              ))}

              {whoFliesHere.alliances.length === 0 &&
                whoFliesHere.corporations.map(group => (
                  <div key={`c-${group.id}`} className="flex justify-between gap-2">
                    <span className="text-stone-300 truncate">{group.name}</span>
                    <span className="text-stone-500 shrink-0">{group.kills}</span>
                  </div>
                ))}
            </div>
          )}
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
