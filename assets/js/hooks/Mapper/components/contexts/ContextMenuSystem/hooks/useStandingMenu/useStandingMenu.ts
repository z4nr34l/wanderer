import { MenuItem } from 'primereact/menuitem';
import { PrimeIcons } from 'primereact/api';
import { useCallback, useRef } from 'react';
import clsx from 'clsx';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { getSystemStaticInfo } from '@/hooks/Mapper/mapRootProvider/hooks/useLoadSystemStatic';
import { OutCommand } from '@/hooks/Mapper/types';
import { GRADIENT_MENU_ACTIVE_CLASSES } from '@/hooks/Mapper/constants.ts';
import {
  AllianceStanding,
  createStandingId,
  findStanding,
  parseAllianceStandings,
  StandingBand,
  standingBand,
} from '@/hooks/Mapper/constants/standings.ts';
import { UserSettingsRemoteProps } from '@/hooks/Mapper/constants/userSettings.ts';

// the presets worth a click - the bands, not every number in between
const STANDING_PRESETS: { label: string; value: number; band: StandingBand }[] = [
  { label: 'Friendly', value: 10, band: StandingBand.friendly },
  { label: 'Neutral', value: 0, band: StandingBand.neutral },
  { label: 'Warning', value: -5, band: StandingBand.warning },
  { label: 'Danger', value: -10, band: StandingBand.danger },
];

const BAND_ICON_CLASSES: Record<StandingBand, string> = {
  [StandingBand.friendly]: 'text-blue-400',
  [StandingBand.neutral]: 'text-stone-400',
  [StandingBand.warning]: 'text-orange-400',
  [StandingBand.danger]: 'text-red-400',
};

/**
 * Setting a holder's standing from the system you are looking at, rather than opening settings
 * and typing the ticker in by hand. Only shows for systems that actually have a holder.
 */
export const useStandingMenu = (systemId: string | undefined): (() => MenuItem | null) => {
  const {
    outCommand,
    userRemoteSettings: { userRemoteSettings, setUserRemoteSettings },
  } = useMapRootState();

  const ref = useRef({ outCommand, userRemoteSettings, setUserRemoteSettings, systemId });
  ref.current = { outCommand, userRemoteSettings, setUserRemoteSettings, systemId };

  const save = useCallback(async (next: AllianceStanding[]) => {
    const { outCommand, userRemoteSettings, setUserRemoteSettings } = ref.current;

    const updated = { ...userRemoteSettings, [UserSettingsRemoteProps.sovereignty_standings]: next };

    await outCommand({ type: OutCommand.updateUserSettings, data: updated });
    setUserRemoteSettings(updated);
  }, []);

  return useCallback(() => {
    const { systemId, userRemoteSettings } = ref.current;
    const sovereignty = systemId ? getSystemStaticInfo(systemId)?.sovereignty : undefined;

    if (!sovereignty?.alliance_ticker) {
      return null;
    }

    const standings = parseAllianceStandings(userRemoteSettings.sovereignty_standings);
    const current = findStanding(sovereignty, standings);

    // an alliance is one entry: setting a standing replaces whatever it had, ticker or name
    const withoutAlliance = () => {
      const ticker = sovereignty.alliance_ticker.toLowerCase();
      const name = sovereignty.alliance_name?.toLowerCase();

      return standings.filter(x => {
        const match = x.alliance.trim().toLowerCase();

        return match !== ticker && match !== name;
      });
    };

    const items: MenuItem[] = STANDING_PRESETS.map(preset => ({
      label: preset.label,
      icon: clsx(PrimeIcons.CIRCLE_FILL, BAND_ICON_CLASSES[preset.band]),
      className: clsx({
        [GRADIENT_MENU_ACTIVE_CLASSES]: current !== undefined && standingBand(current) === preset.band,
      }),
      command: () =>
        save([
          ...withoutAlliance(),
          { id: createStandingId(), alliance: sovereignty.alliance_ticker, standing: preset.value },
        ]),
    }));

    if (current !== undefined) {
      items.push({
        label: 'Clear',
        icon: PrimeIcons.BAN,
        command: () => save(withoutAlliance()),
      });
    }

    return {
      label: `Standing: ${sovereignty.alliance_ticker}`,
      icon: PrimeIcons.FLAG,
      className: clsx({ [GRADIENT_MENU_ACTIVE_CLASSES]: current !== undefined }),
      items,
    };
  }, [save]);
};
