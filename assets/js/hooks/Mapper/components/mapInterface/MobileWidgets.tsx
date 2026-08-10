import { useCallback, useMemo, useState } from 'react';
import clsx from 'clsx';
import { WindowProps } from '@/hooks/Mapper/components/ui-kit/WindowManager/types.ts';
import {
  WIDGET_ICONS,
  WIDGETS_CHECKBOXES_PROPS,
  WidgetsIds,
} from '@/hooks/Mapper/components/mapInterface/constants.tsx';
import classes from './MobileWidgets.module.scss';

export interface MobileWidgetsProps {
  widgets: WindowProps[];
}

const widgetLabel = (id: WindowProps['id']) =>
  WIDGETS_CHECKBOXES_PROPS.find(x => x.id === id)?.label ?? String(id);

const widgetIcon = (id: WindowProps['id']) => WIDGET_ICONS[id as WidgetsIds] ?? 'pi pi-window-maximize';

/**
 * On a phone the floating windows cover the map and there is no way to shove them aside, so the
 * widgets live in a dock along the bottom and open one at a time over the map.
 */
export const MobileWidgets = ({ widgets }: MobileWidgetsProps) => {
  const [openId, setOpenId] = useState<WindowProps['id'] | null>(null);

  const open = useMemo(() => widgets.find(x => x.id === openId), [openId, widgets]);

  const handleToggle = useCallback((id: WindowProps['id']) => {
    setOpenId(prev => (prev === id ? null : id));
  }, []);

  const handleClose = useCallback(() => setOpenId(null), []);

  if (widgets.length === 0) {
    return null;
  }

  return (
    <div className={classes.Root}>
      {open && (
        <>
          <div className={classes.Backdrop} onClick={handleClose} />

          <div className={classes.Sheet}>
            {/* the widget brings its own header, so this bar only has to say "drag me down" */}
            <div className={clsx(classes.SheetBar, 'flex items-center justify-between px-2 shrink-0')}>
              <span className="w-9" />
              <span className={classes.Grip} />
              <button
                type="button"
                aria-label="Close"
                className="w-9 flex items-center justify-end text-stone-400"
                onClick={handleClose}
              >
                <i className="pi pi-times text-[12px]" />
              </button>
            </div>

            <div className="flex-1 min-h-0">{open.content(open)}</div>
          </div>
        </>
      )}

      <div
        className={clsx(
          classes.Dock,
          'flex items-stretch gap-1 px-1 overflow-x-auto custom-scrollbar',
          'border-t border-gray-500 border-opacity-30',
          'bg-opacity-80 bg-neutral-900 backdrop-blur-md',
        )}
      >
        {widgets.map(widget => {
          const isOpen = widget.id === openId;

          return (
            <button
              key={widget.id}
              type="button"
              className={clsx(
                classes.DockButton,
                'flex flex-col items-center justify-center gap-0.5 px-2 rounded',
                isOpen ? 'text-sky-300 bg-white bg-opacity-10' : 'text-stone-400',
              )}
              onClick={() => handleToggle(widget.id)}
            >
              <i className={clsx(widgetIcon(widget.id), 'text-[15px]')} />
              <span className="text-[10px] leading-none whitespace-nowrap">{widgetLabel(widget.id)}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
};
