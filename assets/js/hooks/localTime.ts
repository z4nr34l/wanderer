import { defineHook } from './liveView';

export default defineHook({
  mounted() {
    this.updated();
  },

  updated() {
    const dt = new Date(this.el.textContent);
    const options = { hour12: false };
    this.el.textContent = `${dt.toLocaleString('en-US', options)}`;
    this.el.classList.remove('invisible');
  },
});
