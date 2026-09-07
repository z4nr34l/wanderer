import { act, createElement } from 'react';
import { createRoot, Root } from 'react-dom/client';
import { LongPressEvent, useLongPress, UseLongPressOptions } from './useLongPress';

// react-dom/test-utils' act() only recognises the environment as async-capable with this
// flag set; without it React 18 warns on every render even though act() is used correctly
declare global {
  // eslint-disable-next-line no-var
  var IS_REACT_ACT_ENVIRONMENT: boolean;
}
globalThis.IS_REACT_ACT_ENVIRONMENT = true;

// Mounts a throwaway component so the hook gets a real render cycle (refs, effects, timers)
// without pulling in a component testing library the project doesn't otherwise use.
const renderLongPress = (onLongPress: (event: LongPressEvent) => void, options?: UseLongPressOptions) => {
  let handlers!: ReturnType<typeof useLongPress>;

  const TestComponent = () => {
    handlers = useLongPress(onLongPress, options);
    return null;
  };

  const container = document.createElement('div');
  let root: Root;
  act(() => {
    root = createRoot(container);
    root.render(createElement(TestComponent));
  });

  return {
    get handlers() {
      return handlers;
    },
    unmount: () => act(() => root.unmount()),
  };
};

const pointerEvent = (
  overrides: Partial<{
    pointerType: string;
    pointerId: number;
    isPrimary: boolean;
    clientX: number;
    clientY: number;
  }> = {},
) =>
  ({
    pointerType: 'touch',
    pointerId: 1,
    // the browser marks the first finger of a gesture primary and every later one not
    isPrimary: true,
    clientX: 0,
    clientY: 0,
    pageX: 0,
    pageY: 0,
    target: document.createElement('div'),
    currentTarget: document.createElement('div'),
    ...overrides,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  }) as any;

const mouseEvent = () =>
  ({ preventDefault: jest.fn(), stopPropagation: jest.fn() }) as unknown as Parameters<
    ReturnType<typeof useLongPress>['onClickCapture']
  >[0];

describe('useLongPress', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('fires onLongPress after the delay when the touch stays still', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450 });

    act(() => {
      handlers.onPointerDown(pointerEvent({ clientX: 10, clientY: 10 }));
    });
    expect(onLongPress).not.toHaveBeenCalled();

    act(() => {
      jest.advanceTimersByTime(450);
    });
    expect(onLongPress).toHaveBeenCalledTimes(1);
  });

  it('ignores mouse and pen pointers so desktop right-click keeps working', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress);

    act(() => {
      handlers.onPointerDown(pointerEvent({ pointerType: 'mouse' }));
      jest.advanceTimersByTime(1000);
    });

    expect(onLongPress).not.toHaveBeenCalled();
  });

  it('cancels the hold once the finger drifts past the move tolerance', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450, moveTolerance: 10 });

    act(() => {
      handlers.onPointerDown(pointerEvent({ clientX: 0, clientY: 0 }));
      handlers.onPointerMove(pointerEvent({ clientX: 20, clientY: 0 }));
      jest.advanceTimersByTime(450);
    });

    expect(onLongPress).not.toHaveBeenCalled();
  });

  it('does not cancel the hold for a drift within the move tolerance', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450, moveTolerance: 10 });

    act(() => {
      handlers.onPointerDown(pointerEvent({ clientX: 0, clientY: 0 }));
      handlers.onPointerMove(pointerEvent({ clientX: 4, clientY: 4 }));
      jest.advanceTimersByTime(450);
    });

    expect(onLongPress).toHaveBeenCalledTimes(1);
  });

  it('cancels the hold when the touch lifts early', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450 });

    act(() => {
      handlers.onPointerDown(pointerEvent());
      jest.advanceTimersByTime(200);
      handlers.onPointerUp(pointerEvent());
      jest.advanceTimersByTime(250);
    });

    expect(onLongPress).not.toHaveBeenCalled();
  });

  it('cancels the hold when a second finger lands, and does not fire when the first lifts either', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450 });

    act(() => {
      handlers.onPointerDown(pointerEvent({ pointerId: 1 }));
      // a pinch or two-finger pan starting mid-hold
      handlers.onPointerDown(pointerEvent({ pointerId: 2, isPrimary: false }));
      jest.advanceTimersByTime(450);
    });
    expect(onLongPress).not.toHaveBeenCalled();

    act(() => {
      handlers.onPointerUp(pointerEvent({ pointerId: 1 }));
      jest.advanceTimersByTime(450);
    });
    expect(onLongPress).not.toHaveBeenCalled();
  });

  it('holds normally again once every pointer from an aborted multi-touch has lifted', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450 });

    act(() => {
      handlers.onPointerDown(pointerEvent({ pointerId: 1 }));
      handlers.onPointerDown(pointerEvent({ pointerId: 2, isPrimary: false }));
      handlers.onPointerUp(pointerEvent({ pointerId: 1 }));
      handlers.onPointerUp(pointerEvent({ pointerId: 2 }));
    });

    // a fresh, single-finger hold afterwards should work as usual
    act(() => {
      handlers.onPointerDown(pointerEvent({ pointerId: 3, clientX: 0, clientY: 0 }));
      jest.advanceTimersByTime(450);
    });
    expect(onLongPress).toHaveBeenCalledTimes(1);
  });

  it('recovers from a pointer whose pointerup the browser never delivered', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450 });

    act(() => {
      handlers.onPointerDown(pointerEvent({ pointerId: 1 }));
      handlers.onPointerDown(pointerEvent({ pointerId: 2, isPrimary: false }));
      // only finger 2 reports lifting; finger 1's pointerup is lost (app switch mid-hold)
      handlers.onPointerUp(pointerEvent({ pointerId: 2, isPrimary: false }));
    });

    // the next gesture starts with a primary pointer, which must not be blocked by the leak
    act(() => {
      handlers.onPointerDown(pointerEvent({ pointerId: 3, clientX: 0, clientY: 0 }));
      jest.advanceTimersByTime(450);
    });
    expect(onLongPress).toHaveBeenCalledTimes(1);
  });

  it('ignores a move from a pointer other than the one being tracked', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450, moveTolerance: 10 });

    act(() => {
      handlers.onPointerDown(pointerEvent({ pointerId: 1, clientX: 0, clientY: 0 }));
      // a second finger that never registered a pointerdown here (e.g. started elsewhere)
      // moving should not be able to cancel pointer 1's hold
      handlers.onPointerMove(pointerEvent({ pointerId: 2, clientX: 100, clientY: 100 }));
      jest.advanceTimersByTime(450);
    });

    expect(onLongPress).toHaveBeenCalledTimes(1);
  });

  it('cancels the hold on pointercancel', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450 });

    act(() => {
      handlers.onPointerDown(pointerEvent());
      jest.advanceTimersByTime(200);
      handlers.onPointerCancel(pointerEvent());
      jest.advanceTimersByTime(250);
    });

    expect(onLongPress).not.toHaveBeenCalled();
  });

  it('swallows the mousedown/mouseup/click synthesized right after a long press fires', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450 });

    act(() => {
      handlers.onPointerDown(pointerEvent());
      jest.advanceTimersByTime(450);
    });

    const mousedown = mouseEvent();
    const mouseup = mouseEvent();
    const click = mouseEvent();
    act(() => {
      // this is the exact order a touch device synthesizes after the finger lifts
      handlers.onMouseDownCapture(mousedown);
      handlers.onMouseUpCapture(mouseup);
      handlers.onClickCapture(click);
    });

    expect(mousedown.preventDefault).toHaveBeenCalled();
    expect(mousedown.stopPropagation).toHaveBeenCalled();
    expect(mouseup.preventDefault).toHaveBeenCalled();
    expect(click.preventDefault).toHaveBeenCalled();
    expect(click.stopPropagation).toHaveBeenCalled();
  });

  it('leaves an ordinary click, mousedown and mouseup alone when no long press has fired', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress);

    const mousedown = mouseEvent();
    const click = mouseEvent();
    act(() => {
      handlers.onMouseDownCapture(mousedown);
      handlers.onClickCapture(click);
    });

    expect(mousedown.preventDefault).not.toHaveBeenCalled();
    expect(click.preventDefault).not.toHaveBeenCalled();
    expect(click.stopPropagation).not.toHaveBeenCalled();
  });

  it('only swallows one synthesized sequence per press', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450 });

    act(() => {
      handlers.onPointerDown(pointerEvent());
      jest.advanceTimersByTime(450);
    });

    const firstClick = mouseEvent();
    const secondClick = mouseEvent();

    act(() => {
      handlers.onClickCapture(firstClick);
      handlers.onClickCapture(secondClick);
    });

    expect(firstClick.preventDefault).toHaveBeenCalled();
    expect(secondClick.preventDefault).not.toHaveBeenCalled();
  });

  it('swallows the native contextmenu Android fires around the same time the hold does', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450 });

    act(() => {
      handlers.onPointerDown(pointerEvent());
      jest.advanceTimersByTime(450);
    });

    // on Android this native event arrives before the synthesized click
    const contextmenu = mouseEvent();
    act(() => {
      handlers.onContextMenuCapture(contextmenu);
    });

    expect(contextmenu.preventDefault).toHaveBeenCalled();
    expect(contextmenu.stopPropagation).toHaveBeenCalled();

    // the flag survives the contextmenu; only click retires it
    const click = mouseEvent();
    act(() => {
      handlers.onClickCapture(click);
    });
    expect(click.preventDefault).toHaveBeenCalled();
  });

  it('leaves a real contextmenu alone when no long press fired, so desktop right-click is unaffected', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress);

    const contextmenu = mouseEvent();
    act(() => {
      handlers.onContextMenuCapture(contextmenu);
    });

    expect(contextmenu.preventDefault).not.toHaveBeenCalled();
    expect(contextmenu.stopPropagation).not.toHaveBeenCalled();
  });

  it('clears a stale fired flag on the next pointerdown even when it is not a touch, so a mouse click on a hybrid device is never swallowed', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450 });

    act(() => {
      handlers.onPointerDown(pointerEvent());
      jest.advanceTimersByTime(450);
    });

    // a plain mouse click arrives on the same hybrid device before anything else clears the flag
    act(() => {
      handlers.onPointerDown(pointerEvent({ pointerType: 'mouse' }));
    });

    const click = mouseEvent();
    act(() => {
      handlers.onClickCapture(click);
    });

    expect(click.preventDefault).not.toHaveBeenCalled();
  });

  it('clears a stale fired flag on the next real press even if no click ever arrived', () => {
    const onLongPress = jest.fn();
    const { handlers } = renderLongPress(onLongPress, { delay: 450 });

    act(() => {
      handlers.onPointerDown(pointerEvent());
      jest.advanceTimersByTime(450);
    });

    // a second long press elsewhere, still no click from the first one in between
    act(() => {
      handlers.onPointerDown(pointerEvent());
    });

    const click = mouseEvent();
    act(() => {
      handlers.onClickCapture(click);
    });

    expect(click.preventDefault).not.toHaveBeenCalled();
  });

  it('passes the pointer position through for PrimeReact ContextMenu.show()', () => {
    let received: LongPressEvent | undefined;
    const { handlers } = renderLongPress(event => {
      received = event;
    });

    act(() => {
      handlers.onPointerDown({
        pointerType: 'touch',
        clientX: 42,
        clientY: 24,
        pageX: 142,
        pageY: 124,
        target: 'target-el',
        currentTarget: 'current-target-el',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
      } as any);
      jest.advanceTimersByTime(450);
    });

    expect(received).toMatchObject({
      pageX: 142,
      pageY: 124,
      clientX: 42,
      clientY: 24,
      target: 'target-el',
      currentTarget: 'current-target-el',
    });
    expect(typeof received?.preventDefault).toBe('function');
    expect(typeof received?.stopPropagation).toBe('function');
  });
});
