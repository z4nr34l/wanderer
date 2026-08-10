import { useMemo } from 'react';
import { WindowManager } from '@/hooks/Mapper/components/ui-kit/WindowManager';
import { DEFAULT_WIDGETS } from '@/hooks/Mapper/components/mapInterface/constants.tsx';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { useIsMobile } from '@/hooks/Mapper/hooks/useIsMobile.ts';
import { MobileWidgets } from '@/hooks/Mapper/components/mapInterface/MobileWidgets.tsx';

export const MapInterface = () => {
  const { windowsSettings, updateWidgetSettings } = useMapRootState();
  const isMobile = useIsMobile();

  const items = useMemo(() => {
    if (Object.keys(windowsSettings).length === 0) {
      return [];
    }

    return windowsSettings.windows
      .map(x => ({ ...x, content: DEFAULT_WIDGETS.find(y => y.id === x.id)?.content }))
      // a stored layout can name a widget this version no longer has - drop it instead of
      // rendering a window with nothing to call
      .filter((x): x is typeof x & { content: NonNullable<typeof x.content> } => x.content != null)
      .filter(x => windowsSettings.visible.some(j => x.id === j));
  }, [windowsSettings]);

  // dragging and resizing windows needs a mouse and screen room, so a phone gets a dock instead
  if (isMobile) {
    return <MobileWidgets widgets={items} />;
  }

  return (
    <WindowManager
      windows={items}
      viewPort={windowsSettings.viewPort}
      dragSelector=".react-grid-dragHandleExample"
      onChange={updateWidgetSettings}
    />
  );
};
