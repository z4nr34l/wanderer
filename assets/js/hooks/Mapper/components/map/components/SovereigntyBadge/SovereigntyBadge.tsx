import clsx from 'clsx';
import { SovereigntyInfo } from '@/hooks/Mapper/types';
import { WdTooltipWrapper } from '@/hooks/Mapper/components/ui-kit/WdTooltipWrapper';
import { TooltipPosition } from '@/hooks/Mapper/components/ui-kit';
import classes from './SovereigntyBadge.module.scss';

export interface SovereigntyBadgeProps {
  sovereignty?: SovereigntyInfo | null;
  className?: string;
}

/**
 * Who holds a null sec system. The ticker is what people navigate by, so that is what the node
 * shows; the full alliance name sits in the tooltip.
 */
export const SovereigntyBadge = ({ sovereignty, className }: SovereigntyBadgeProps) => {
  if (!sovereignty?.alliance_ticker) {
    return null;
  }

  return (
    <WdTooltipWrapper content={sovereignty.alliance_name} position={TooltipPosition.top}>
      <span className={clsx(classes.Badge, className)}>{sovereignty.alliance_ticker}</span>
    </WdTooltipWrapper>
  );
};
