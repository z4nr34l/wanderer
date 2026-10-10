import { useEffect } from 'react';

export const useSkipContextMenu = () => {
  useEffect(() => {
    function handleContextMenu(e: Event) {
      e.preventDefault();
    }

    window.addEventListener(`contextmenu`, handleContextMenu);

    return () => {
      window.removeEventListener(`contextmenu`, handleContextMenu);
    };
  }, []);
};
