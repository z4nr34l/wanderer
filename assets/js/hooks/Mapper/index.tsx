import { createRoot, Root } from 'react-dom/client';
import { defineHook } from '../liveView';
import Mapper, { MapRootHooks } from './MapRoot';

const LAST_VERSION_KEY = 'wandererLastVersion';
const UI_LOADED_EVENT = 'ui_loaded';

export default defineHook({
  _rootEl: null as Root | null,
  _errorCount: 0,

  mounted() {
    // create react root element
    const rootEl = document.getElementById(this.el.id);
    const activeVersion = localStorage.getItem(LAST_VERSION_KEY);
    this._rootEl = createRoot(rootEl!);

    const handleError = (error: Error, componentStack: string) => {
      this.pushEvent('log_map_error', { error: error.message, componentStack });
    };

    this.render({
      handleEvent: this.handleEventWrapper.bind(this),
      pushEvent: this.pushEvent.bind(this),
      pushEventAsync: this.pushEventAsync.bind(this),
      onError: handleError,
    });

    this.pushEvent(UI_LOADED_EVENT, { version: activeVersion });
  },

  handleEventWrapper(event: string, handler: (payload: unknown) => void) {
    this.handleEvent(event, (body: unknown) => {
      handler(body);
    });
  },

  reconnected() {
    const activeVersion = localStorage.getItem(LAST_VERSION_KEY);
    this.pushEvent(UI_LOADED_EVENT, { version: activeVersion });
  },

  async pushEventAsync(event: string, payload: object) {
    return new Promise(accept => {
      this.pushEvent(event, payload, reply => {
        accept(reply);
      });
    });
  },

  render(hooks: MapRootHooks) {
    this._rootEl!.render(<Mapper hooks={hooks} />);
  },

  destroyed() {
    this._rootEl!.unmount();
  },
});
