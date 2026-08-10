import { useEffect, useState } from 'react';

// The floating windows need room beside the map. Under this width they sit on top of it instead,
// which leaves nothing to drag them out of the way with on a touch screen.
export const MOBILE_BREAKPOINT = 768;

const QUERY = `(max-width: ${MOBILE_BREAKPOINT}px)`;

export const useIsMobile = () => {
  const [isMobile, setIsMobile] = useState(() => window.matchMedia(QUERY).matches);

  useEffect(() => {
    const mql = window.matchMedia(QUERY);
    // the query is the source of truth; resize is here because not every browser fires the
    // media query change reliably (and neither does a devtools viewport override)
    const handleChange = () => setIsMobile(mql.matches);

    handleChange();
    mql.addEventListener('change', handleChange);
    window.addEventListener('resize', handleChange);

    return () => {
      mql.removeEventListener('change', handleChange);
      window.removeEventListener('resize', handleChange);
    };
  }, []);

  return isMobile;
};
