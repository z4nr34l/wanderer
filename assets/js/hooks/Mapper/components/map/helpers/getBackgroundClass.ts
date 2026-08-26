import { isZarzakhSpace } from '@/hooks/Mapper/components/map/helpers/isZarzakhSpace.ts';
import {
  SECURITY_BACKGROUND_CLASSES,
  SYSTEM_CLASS_BACKGROUND_CLASSES,
  WORMHOLE_CLASS_BACKGROUND_CLASSES,
} from '@/hooks/Mapper/components/map/constants.ts';
import { isKnownSpace } from '@/hooks/Mapper/components/map/helpers/isKnownSpace.ts';
import { isWormholeSpace } from '@/hooks/Mapper/components/map/helpers/isWormholeSpace.ts';

export const getBackgroundClass = (systemClass: number, security: string) => {
  if (isZarzakhSpace(systemClass)) {
    return SYSTEM_CLASS_BACKGROUND_CLASSES[systemClass];
  }

  if (isKnownSpace(systemClass)) {
    return SECURITY_BACKGROUND_CLASSES[security];
  }

  if (isWormholeSpace(systemClass)) {
    return WORMHOLE_CLASS_BACKGROUND_CLASSES[systemClass];
  }

  // Syndicate and the other NPC pockets carry no class of their own, and a system with no
  // colour is a system nobody can see on a route - their security still says what they are
  return SYSTEM_CLASS_BACKGROUND_CLASSES[systemClass] || SECURITY_BACKGROUND_CLASSES[security] || '';
};
