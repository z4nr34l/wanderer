import {
  PointerEvent as ReactPointerEvent,
  MouseEvent as ReactMouseEvent,
  useCallback,
  useEffect,
  useRef,
} from 'react';

// iOS Safari never fires `contextmenu` on a long-press, and Android's own version of it is
// unreliable inside a canvas like React Flow's. This is how touch gets the same menus a
// right-click opens on desktop.
const DEFAULT_DELAY_MS = 450;

// mirrors the `nodeDragThreshold` the map already gives React Flow, so a finger that is
// about to drag a node reads the same way in both places
const DEFAULT_MOVE_TOLERANCE_PX = 10;

// PrimeReact's ContextMenu.show() only ever reads pageX/pageY off the event it's given (and
// calls preventDefault/stopPropagation on it), so that's all a long press has to fake to be
// indistinguishable from a real contextmenu event by the time it reaches show().
export interface LongPressEvent {
  pageX: number;
  pageY: number;
  clientX: number;
  clientY: number;
  target: EventTarget | null;
  currentTarget: EventTarget | null;
  preventDefault: () => void;
  stopPropagation: () => void;
}

export interface UseLongPressOptions {
  delay?: number;
  moveTolerance?: number;
}

export interface LongPressHandlers {
  onPointerDown: (event: ReactPointerEvent) => void;
  onPointerMove: (event: ReactPointerEvent) => void;
  onPointerUp: (event: ReactPointerEvent) => void;
  onPointerCancel: (event: ReactPointerEvent) => void;
  onMouseDownCapture: (event: ReactMouseEvent) => void;
  onMouseUpCapture: (event: ReactMouseEvent) => void;
  onClickCapture: (event: ReactMouseEvent) => void;
  onContextMenuCapture: (event: ReactMouseEvent) => void;
}

/**
 * Turns a still touch held down for `delay` ms into a call to `onLongPress`, carrying enough
 * of the pointer position for PrimeReact's ContextMenu to show() at the right spot.
 *
 * Mouse and pen pointers are ignored entirely, so desktop right-click keeps working unchanged.
 * The hold is cancelled if the finger moves past `moveTolerance` px (a real drag or pan) or is
 * lifted early (an ordinary tap). A second pointer landing while one is already down (a pinch,
 * or a two-finger pan) cancels the hold too and blocks a new one from starting until every
 * pointer has lifted, so a pinch can never open a context menu.
 *
 * Once a press fires, lifting the finger still makes the browser synthesize a mousedown,
 * mouseup and click on whatever was under it (that's how touch has worked with mouse-only code
 * since forever). Left alone, that mousedown is what resets the map's own context-menu tracker
 * and the click is what selecting or deselecting a node runs on, closing the menu this long
 * press just opened. `onMouseDownCapture`/`onMouseUpCapture`/`onClickCapture` swallow that one
 * synthesized sequence; a fresh pointerdown always clears the flag regardless of pointer type,
 * so it can never survive to swallow an unrelated later click.
 *
 * Android Chrome additionally fires a real `contextmenu` DOM event around the same ~500ms mark
 * (its own d3-zoom/d3-drag never preventDefault touchstart, only touchmove, so the browser still
 * runs its default long-press action). That native event arrives before the synthesized click,
 * while `firedRecently` is still set from the timer above, so `onContextMenuCapture` can use the
 * same flag to swallow it. Left alone it would both open the OS/browser menu and let React Flow's
 * onNodeContextMenu/onPaneContextMenu/onEdgeContextMenu/onSelectionContextMenu call `show()` a
 * second time on an already-visible PrimeReact menu, which makes it hide and reshow (a flicker).
 */
export const useLongPress = (
  onLongPress: (event: LongPressEvent) => void,
  { delay = DEFAULT_DELAY_MS, moveTolerance = DEFAULT_MOVE_TOLERANCE_PX }: UseLongPressOptions = {},
): LongPressHandlers => {
  const state = useRef({
    timer: null as ReturnType<typeof setTimeout> | null,
    startX: 0,
    startY: 0,
    tracking: false,
    // true from the moment a press fires until the click it synthesizes is swallowed
    firedRecently: false,
    // every pointer currently down, touch or not; a second one down means a pinch or a
    // multi-finger pan rather than a hold, until every finger lifts again
    activePointers: new Set<number>(),
    // the single pointer a hold is being timed for, if any
    trackedPointerId: null as number | null,
  });

  const clearTimer = useCallback(() => {
    if (state.current.timer !== null) {
      clearTimeout(state.current.timer);
      state.current.timer = null;
    }
    state.current.tracking = false;
  }, []);

  // a hook that unmounts mid-hold shouldn't leave a stray timer firing into nothing
  useEffect(() => clearTimer, [clearTimer]);

  const onPointerDown = useCallback(
    (event: ReactPointerEvent) => {
      // any fresh pointer interaction retires a stale flag from a previous press, touch or
      // not, so a plain mouse click on a hybrid device can never be swallowed by it
      state.current.firedRecently = false;

      // a primary pointer only ever starts a brand new gesture (every earlier finger is up by
      // then), so it is a safe point to forget pointers whose pointerup/pointercancel the
      // browser dropped (app switch mid-hold, OS killing the stream); without this purge one
      // leaked id would make every later single-finger hold look like multi-touch
      if (event.isPrimary) {
        state.current.activePointers.clear();
      }

      state.current.activePointers.add(event.pointerId);

      // a second finger landing means this is a pinch or a multi-finger pan, not a hold; drop
      // whatever was being timed and don't start timing this one either, until every pointer
      // now down has lifted (see onPointerUp/onPointerCancel)
      if (state.current.activePointers.size > 1) {
        clearTimer();
        state.current.trackedPointerId = null;
        return;
      }

      // the mouse and pen still have a real contextmenu event to fall back on
      if (event.pointerType !== 'touch') {
        return;
      }

      const { clientX, clientY, pageX, pageY, target, currentTarget } = event;
      state.current.startX = clientX;
      state.current.startY = clientY;
      state.current.tracking = true;
      state.current.trackedPointerId = event.pointerId;

      state.current.timer = setTimeout(() => {
        // still down, and never moved past the tolerance, so this is a hold rather than a
        // tap or the start of a drag
        state.current.tracking = false;
        state.current.timer = null;
        state.current.firedRecently = true;

        onLongPress({
          pageX,
          pageY,
          clientX,
          clientY,
          target,
          currentTarget,
          // the real preventDefault/stopPropagation already ran (or didn't matter) by the time
          // this fires; callers that need them are given no-ops so they can call them freely
          preventDefault: () => {},
          stopPropagation: () => {},
        });
      }, delay);
    },
    [clearTimer, delay, onLongPress],
  );

  const onPointerMove = useCallback(
    (event: ReactPointerEvent) => {
      if (!state.current.tracking || event.pointerId !== state.current.trackedPointerId) {
        return;
      }

      const dx = event.clientX - state.current.startX;
      const dy = event.clientY - state.current.startY;

      // a finger that has moved this far is panning the map or dragging a node, not holding
      // still for a menu
      if (Math.hypot(dx, dy) > moveTolerance) {
        clearTimer();
      }
    },
    [clearTimer, moveTolerance],
  );

  const onPointerUp = useCallback(
    (event: ReactPointerEvent) => {
      state.current.activePointers.delete(event.pointerId);

      // a different finger lifting (the other half of a pinch, say) doesn't affect whatever
      // this one is or isn't timing
      if (event.pointerId !== state.current.trackedPointerId) {
        return;
      }

      // lifted before the hold matured: an ordinary tap, let it click through as usual
      state.current.trackedPointerId = null;
      clearTimer();
    },
    [clearTimer],
  );

  const onPointerCancel = useCallback(
    (event: ReactPointerEvent) => {
      state.current.activePointers.delete(event.pointerId);

      if (event.pointerId !== state.current.trackedPointerId) {
        return;
      }

      state.current.trackedPointerId = null;
      clearTimer();
    },
    [clearTimer],
  );

  const swallowIfJustFired = useCallback((event: ReactMouseEvent) => {
    if (state.current.firedRecently) {
      event.preventDefault();
      event.stopPropagation();
    }
  }, []);

  const onMouseDownCapture = swallowIfJustFired;
  const onMouseUpCapture = swallowIfJustFired;

  // Android fires this natively around the same time the hold timer above does; swallowing it
  // stops both the OS/browser menu and a second show() on an already-visible PrimeReact menu.
  // Left for click to clear the flag, since the native contextmenu still precedes the
  // synthesized click on Android.
  const onContextMenuCapture = swallowIfJustFired;

  const onClickCapture = useCallback(
    (event: ReactMouseEvent) => {
      // click is the last event in the synthesized sequence, so this is where the flag is
      // finally cleared; if a browser skips it for some reason, the next real pointerdown
      // clears it anyway
      swallowIfJustFired(event);
      state.current.firedRecently = false;
    },
    [swallowIfJustFired],
  );

  return {
    onPointerDown,
    onPointerMove,
    onPointerUp,
    onPointerCancel,
    onMouseDownCapture,
    onMouseUpCapture,
    onClickCapture,
    onContextMenuCapture,
  };
};
