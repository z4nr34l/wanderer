import { Droppable } from '@shopify/draggable';
import { defineHook } from './liveView';

export default defineHook({
  mounted() {
    let lastDropzone: string | null = null;
    const hook = this;
    const containers = document.querySelectorAll<HTMLElement>('.dropzone');
    const selector = '#' + this.el.id;

    const droppable = new Droppable(containers, {
      delay: 100,
      draggable: '.draggable',
      dropzone: '.dropzone',
      mirror: {
        constrainDimensions: true,
      },
    });

    let droppableOrigin: HTMLElement;

    // --- Draggable events --- //
    droppable.on('drag:start', evt => {
      lastDropzone = null;
      droppableOrigin = evt.originalSource;
    });

    droppable.on('droppable:dropped', evt => {
      if ((droppableOrigin.parentNode as HTMLElement).dataset.dropzone !== evt.dropzone.dataset.dropzone) {
        lastDropzone = evt.dropzone.dataset.dropzone ?? null;
        evt.cancel();
      }
    });

    droppable.on('droppable:stop', () => {
      if (!lastDropzone) {
        return;
      }
      hook.pushEventTo(selector, 'dropped', { draggedId: droppableOrigin.id, dropzoneId: lastDropzone });
    });
  },
});
