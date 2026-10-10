import { defineHook } from './liveView';

export default defineHook({
  mounted() {
    this.pushEvent('restore_show_characters_add_alert', {
      value: localStorage.getItem('wanderer:hide_characters_add_alert') !== 'true',
    });

    document.getElementById('characters-add-alert-hide')?.addEventListener('click', () => {
      localStorage.setItem('wanderer:hide_characters_add_alert', 'true');
    });
  },
});
