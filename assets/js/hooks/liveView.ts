// Minimal typing for the hook instance Phoenix LiveView binds as `this` in client hooks.
export interface ViewHook {
  el: HTMLElement;
  pushEvent(event: string, payload?: object, onReply?: (reply: unknown, ref: number) => void): void;
  pushEventTo(
    selectorOrTarget: string | HTMLElement,
    event: string,
    payload?: object,
    onReply?: (reply: unknown, ref: number) => void,
  ): void;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  handleEvent(event: string, callback: (payload: any) => void): unknown;
}

// Identity helper that types `this` inside hook callbacks as the hook's own members plus ViewHook.
export const defineHook = <T extends object>(hook: T & ThisType<T & ViewHook>): T => hook;
