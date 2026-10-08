import { SovereigntyInfo } from '@/hooks/Mapper/types';
import { WdTooltipWrapper } from '@/hooks/Mapper/components/ui-kit/WdTooltipWrapper';
import { TooltipPosition } from '@/hooks/Mapper/components/ui-kit';
import {
  WdEveEntityPortrait,
  WdEveEntityPortraitSize,
  WdEveEntityPortraitType,
} from '@/hooks/Mapper/components/ui-kit/WdEveEntityPortrait';

export interface SovereigntyBadgeProps {
  sovereignty?: SovereigntyInfo | null;
  // the standing colour the user gave this alliance
  color: string;
  // the chip styling from the node it hangs off, so it matches the label chips exactly
  className?: string;
}

// A faction's name is its own chip: there is no ticker for one, and the name is what anybody
// flying out there would say.
const factionChip = (name: string) =>
  name
    .replace(/^The /, '')
    .split(/\s+/)
    .map(word => word.replace(/[^A-Za-z0-9'-]/g, ''))
    .filter(Boolean)
    .slice(0, 2)
    .join(' ');

/**
 * Who holds a null sec system. The ticker is what people navigate by, so that is what the chip
 * shows; hovering gives the alliance itself - logo, name and ticker.
 *
 * Where no alliance holds the space, the faction whose space it is takes the chip instead - the
 * NPC null regions are most of the null sec nobody claims, and knowing it is Sansha's or the
 * Guristas out there is the whole of what a reader wants from the question.
 */
export const SovereigntyBadge = ({ sovereignty, color, className }: SovereigntyBadgeProps) => {
  if (!sovereignty?.alliance_ticker && sovereignty?.faction_name) {
    return (
      <div className={className} style={{ backgroundColor: color }}>
        <WdTooltipWrapper
          content={
            <div className="flex items-center gap-2">
              <WdEveEntityPortrait
                eveId={String(sovereignty.faction_id)}
                type={WdEveEntityPortraitType.corporation}
                size={WdEveEntityPortraitSize.w33}
              />

              <div className="flex flex-col leading-tight">
                <span className="text-stone-200 text-[12px] font-semibold">{sovereignty.faction_name}</span>
                <span className="text-stone-400 text-[11px]">no alliance holds this space</span>
              </div>
            </div>
          }
          position={TooltipPosition.bottom}
          interactive
        >
          <span className="[text-shadow:_0_1px_0_rgb(0_0_0_/_40%)] italic">
            {factionChip(sovereignty.faction_name)}
          </span>
        </WdTooltipWrapper>
      </div>
    );
  }

  if (!sovereignty?.alliance_ticker) {
    return null;
  }

  const tooltip = (
    <div className="flex items-center gap-2">
      <WdEveEntityPortrait
        eveId={String(sovereignty.alliance_id)}
        type={WdEveEntityPortraitType.alliance}
        size={WdEveEntityPortraitSize.w33}
      />

      <div className="flex flex-col leading-tight">
        <span className="text-stone-200 text-[12px] font-semibold">{sovereignty.alliance_name}</span>
        <span className="text-stone-400 text-[11px]">[{sovereignty.alliance_ticker}] &middot; sovereignty holder</span>
      </div>
    </div>
  );

  return (
    <div className={className} style={{ backgroundColor: color }}>
      <WdTooltipWrapper content={tooltip} position={TooltipPosition.bottom} interactive>
        <span className="[text-shadow:_0_1px_0_rgb(0_0_0_/_40%)]">{sovereignty.alliance_ticker}</span>
      </WdTooltipWrapper>
    </div>
  );
};
