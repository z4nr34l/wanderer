import { SovereigntyInfo } from '@/hooks/Mapper/types';
import { WdTooltipWrapper } from '@/hooks/Mapper/components/ui-kit/WdTooltipWrapper';
import { TooltipPosition } from '@/hooks/Mapper/components/ui-kit';

export interface SovereigntyBadgeProps {
  sovereignty?: SovereigntyInfo | null;
  // the standing colour the user gave this alliance
  color: string;
  // the chip styling from the node it hangs off, so it matches the label chips exactly
  className?: string;
}

/**
 * Who holds a null sec system. The ticker is what people navigate by, so that is what the chip
 * shows; the full alliance name sits in the tooltip.
 */
export const SovereigntyBadge = ({ sovereignty, color, className }: SovereigntyBadgeProps) => {
  if (!sovereignty?.alliance_ticker) {
    return null;
  }

  return (
    <div className={className} style={{ backgroundColor: color }}>
      <WdTooltipWrapper content={sovereignty.alliance_name} position={TooltipPosition.bottom}>
        <span className="[text-shadow:_0_1px_0_rgb(0_0_0_/_40%)]">{sovereignty.alliance_ticker}</span>
      </WdTooltipWrapper>
    </div>
  );
};
