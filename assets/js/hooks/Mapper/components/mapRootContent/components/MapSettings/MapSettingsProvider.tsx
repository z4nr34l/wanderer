import { createContext, ReactNode, useCallback, useContext, useMemo, useRef } from 'react';
import {
  SettingsListItem,
  UserSettings,
  UserSettingsRemote,
} from '@/hooks/Mapper/components/mapRootContent/components/MapSettings/types.ts';
import { UserSettingsRemoteList } from '@/hooks/Mapper/constants/userSettings.ts';
import { OutCommand } from '@/hooks/Mapper/types';
import { PrettySwitchbox } from '@/hooks/Mapper/components/mapRootContent/components/MapSettings/components';
import { Dropdown } from 'primereact/dropdown';
import { InputText } from 'primereact/inputtext';
import { InputNumber } from 'primereact/inputnumber';
import { ColorPicker } from 'primereact/colorpicker';
import { PrimeIcons } from 'primereact/api';
import { WdImgButton } from '@/hooks/Mapper/components/ui-kit/WdImgButton';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { WithChildren } from '@/hooks/Mapper/types/common.ts';
import { FormatTemplateInput } from '@/hooks/Mapper/components/mapRootContent/components/MapSettings/components/FormatTemplateInput.tsx';
import { SystemLabelDefinition } from '@/hooks/Mapper/constants/labels.ts';

export type SettingValue = boolean | number | string | null | Record<string, string> | SystemLabelDefinition[];

type MapSettingsContextType = {
  renderSettingItem: (item: SettingsListItem) => ReactNode;
  updateSetting: (prop: keyof UserSettings, value: SettingValue) => Promise<void>;
  // several remote settings in one save, so they cannot race each other
  updateRemoteSettings: (patch: Partial<UserSettingsRemote>) => Promise<void>;
  setUserRemoteSettings: (settings: UserSettingsRemote) => void;
  settings: UserSettings;
};

const MapSettingsContext = createContext<MapSettingsContextType | undefined>(undefined);

export const MapSettingsProvider = ({ children }: WithChildren) => {
  const {
    outCommand,
    storedSettings: { interfaceSettings, setInterfaceSettings },
    userRemoteSettings: { userRemoteSettings, setUserRemoteSettings },
  } = useMapRootState();

  const mergedSettings: UserSettings = useMemo(() => {
    return {
      ...userRemoteSettings,
      ...interfaceSettings,
    };
  }, [userRemoteSettings, interfaceSettings]);

  const refVars = useRef({
    mergedSettings,
    userRemoteSettings,
    interfaceSettings,
    outCommand,
    setInterfaceSettings,
    setUserRemoteSettings,
  });
  refVars.current = {
    mergedSettings,
    userRemoteSettings,
    interfaceSettings,
    outCommand,
    setInterfaceSettings,
    setUserRemoteSettings,
  };

  const handleSettingChange = useCallback(async (prop: keyof UserSettings, value: SettingValue) => {
    const { userRemoteSettings, interfaceSettings, outCommand, setInterfaceSettings, setUserRemoteSettings } =
      refVars.current;

    // A setting this build does not know - a fork with its own list of keys, an entry left over
    // from a merge - must not end up saved under the name "undefined".
    if (!prop) {
      console.warn('[MapSettings] ignored a setting with no name', value);
      return;
    }

    if (prop === 'system_labels') {
      const response = await outCommand<{ success: boolean; system_labels?: SystemLabelDefinition[] }>({
        type: OutCommand.updateMapSystemLabels,
        data: { system_labels: value },
      });

      if (!response?.success || !response.system_labels) {
        throw new Error('Failed to save map system labels');
      }

      setUserRemoteSettings({
        ...userRemoteSettings,
        system_labels: response.system_labels,
      });
    } else if (UserSettingsRemoteList.includes(prop as any)) {
      const newRemoteSettings = {
        ...userRemoteSettings,
        [prop]: value,
      };
      await outCommand({
        type: OutCommand.updateUserSettings,
        data: newRemoteSettings,
      });
      setUserRemoteSettings(newRemoteSettings);
    } else {
      setInterfaceSettings({
        ...interfaceSettings,
        [prop]: value,
      });
    }
  }, []);

  const updateRemoteSettings = useCallback(async (patch: Partial<UserSettingsRemote>) => {
    const { userRemoteSettings, outCommand, setUserRemoteSettings } = refVars.current;
    const newRemoteSettings = { ...userRemoteSettings, ...patch };

    await outCommand({ type: OutCommand.updateUserSettings, data: newRemoteSettings });
    setUserRemoteSettings(newRemoteSettings);
  }, []);

  const renderSettingItem = useCallback(
    (item: SettingsListItem) => {
      // the same guard as on saving: an item whose setting does not exist here is skipped rather
      // than taking the whole dialog - and the map behind it - down with it
      if (!item.prop) {
        console.warn('[MapSettings] skipped a setting with no name', item.label);
        return null;
      }

      if (item.dependsOn) {
        const dependsOnValue = refVars.current.mergedSettings[item.dependsOn];
        if (!dependsOnValue) {
          return null;
        }
      }

      const currentValue = refVars.current.mergedSettings[item.prop];

      if (item.type === 'checkbox') {
        return (
          <PrettySwitchbox
            key={String(item.prop)}
            label={item.label}
            checked={!!currentValue}
            setChecked={checked => handleSettingChange(item.prop, checked)}
          />
        );
      }

      if (item.type === 'dropdown' && item.options) {
        return (
          <div key={String(item.prop)} className="grid grid-cols-[auto_1fr_auto] items-center">
            <label className="text-[var(--gray-200)] text-[13px] select-none">{item.label}:</label>
            <div className="border-b-2 border-dotted border-[#3f3f3f] h-px mx-3" />
            <Dropdown
              className="text-sm"
              value={currentValue}
              options={item.options}
              scrollHeight={item.dropdownScrollHeight}
              onChange={e => handleSettingChange(item.prop, e.value)}
              placeholder="Select a theme"
            />
          </div>
        );
      }

      if (item.type === 'template') {
        return (
          <FormatTemplateInput
            key={String(item.prop)}
            label={item.label}
            value={(currentValue as string) || ''}
            placeholder={item.placeholder}
            helperText={item.helperText}
            onChange={value => handleSettingChange(item.prop, value)}
          />
        );
      }

      if (item.type === 'color') {
        const value = (currentValue as string) || '';

        return (
          <div key={String(item.prop)} className="grid grid-cols-[auto_1fr_auto] items-center gap-1">
            <label className="text-[var(--gray-200)] text-[13px] select-none">{item.label}:</label>
            <div className="border-b-2 border-dotted border-[#3f3f3f] h-px mx-3" />
            <div className="flex items-center gap-2">
              <ColorPicker
                format="hex"
                value={value || item.fallback}
                onChange={e => handleSettingChange(item.prop, e.value ? `#${String(e.value).replace('#', '')}` : null)}
              />
              <WdImgButton
                className={PrimeIcons.REPLAY}
                tooltip={{ content: 'Back to the theme' }}
                onClick={() => handleSettingChange(item.prop, null)}
              />
            </div>
          </div>
        );
      }

      if (item.type === 'number') {
        return (
          <div key={String(item.prop)} className="grid grid-cols-[auto_1fr_auto] items-center gap-1">
            <label className="text-[var(--gray-200)] text-[13px] select-none">{item.label}:</label>
            <div className="border-b-2 border-dotted border-[#3f3f3f] h-px mx-3" />
            <div className="flex items-center gap-2">
              <InputNumber
                className="text-sm w-[110px]"
                inputClassName="text-sm w-[70px]"
                value={(currentValue as number) || null}
                min={item.min}
                max={item.max}
                suffix={item.suffix}
                showButtons
                placeholder={item.placeholder ?? 'theme'}
                onValueChange={e => handleSettingChange(item.prop, e.value ?? null)}
              />
              {/* the spinner stops at its minimum, so this is the only way back to the theme */}
              <WdImgButton
                className={PrimeIcons.REPLAY}
                tooltip={{ content: 'Back to the theme' }}
                onClick={() => handleSettingChange(item.prop, null)}
              />
            </div>
          </div>
        );
      }

      if (item.type === 'text') {
        return (
          <div key={String(item.prop)} className="flex flex-col gap-1 w-full mt-2 mb-2">
            {item.label && <label className="text-[var(--gray-200)] text-[13px] select-none">{item.label}</label>}
            <InputText
              className="text-sm w-full"
              defaultValue={(currentValue as string) || ''}
              onBlur={e => handleSettingChange(item.prop, e.target.value)}
              placeholder={item.placeholder}
            />
            {item.helperText && <small className="text-gray-400 text-xs mt-1">{item.helperText}</small>}
          </div>
        );
      }

      return null;
    },
    [handleSettingChange],
  );

  return (
    <MapSettingsContext.Provider
      value={{
        renderSettingItem,
        updateSetting: handleSettingChange,
        updateRemoteSettings,
        setUserRemoteSettings,
        settings: mergedSettings,
      }}
    >
      {children}
    </MapSettingsContext.Provider>
  );
};

export const useMapSettings = () => {
  const context = useContext(MapSettingsContext);
  if (!context) {
    throw new Error('useMapSettings must be used within a MapSettingsProvider');
  }
  return context;
};
