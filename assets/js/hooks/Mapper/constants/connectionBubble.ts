import { CSSProperties } from 'react';

/**
 * The bubble drawn on a bubbled connection end is styled through CSS variables so a theme can
 * dress it up on its own. Anything the user sets in map settings is written onto the map root and
 * wins over the theme; leaving a setting empty hands it back to the theme.
 */
export const BUBBLE_CSS_VARS = {
  color: '--rf-edge-bubble',
  fill: '--rf-edge-bubble-fill',
  size: '--rf-edge-bubble-size',
  border: '--rf-edge-bubble-border',
} as const;

// kept in step with SolarSystemEdge.module.scss, and used when only part of the fill is configured
export const BUBBLE_DEFAULT_COLOR = '#ffb03a';
export const BUBBLE_DEFAULT_OPACITY = 18;

export const BUBBLE_SIZE_RANGE = { min: 8, max: 64 };
export const BUBBLE_BORDER_RANGE = { min: 1, max: 8 };
// zero used to mean "follow the theme" and still does for settings saved before reset existed,
// so the lowest fill a person can choose is 1%
export const BUBBLE_OPACITY_RANGE = { min: 1, max: 100 };

export type ConnectionBubbleSettings = {
  connection_bubble_color?: string | null;
  connection_bubble_size?: number | null;
  connection_bubble_border?: number | null;
  connection_bubble_opacity?: number | null;
};

export const CONNECTION_BUBBLE_KEYS = [
  'connection_bubble_color',
  'connection_bubble_size',
  'connection_bubble_border',
  'connection_bubble_opacity',
] as const;

/**
 * Whether the user has set this field. Empty, zero, null and a key that was never saved at all
 * all mean the same thing - follow the theme - so settings written by any earlier version read
 * correctly, and a reset only has to clear the field.
 */
export const isBubbleSettingSet = (value: unknown): value is string | number =>
  (typeof value === 'string' && value !== '') || (typeof value === 'number' && value > 0);

const hexToRgb = (hex: string) => {
  const value = hex.replace('#', '');

  const full =
    value.length === 3
      ? value
          .split('')
          .map(x => x + x)
          .join('')
      : value;

  if (full.length !== 6 || /[^0-9a-f]/i.test(full)) {
    return undefined;
  }

  return {
    r: parseInt(full.slice(0, 2), 16),
    g: parseInt(full.slice(2, 4), 16),
    b: parseInt(full.slice(4, 6), 16),
  };
};

export const bubbleFillColor = (color: string, opacity: number) => {
  const rgb = hexToRgb(color || BUBBLE_DEFAULT_COLOR);

  if (!rgb) {
    return undefined;
  }

  return `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${opacity / 100})`;
};

/**
 * Builds the style to put on the map root. Only the settings the user actually filled in end up
 * there, so an untouched setting keeps following the theme.
 */
export const bubbleCssVars = (settings: ConnectionBubbleSettings): CSSProperties => {
  const { connection_bubble_color: color, connection_bubble_size: size } = settings;
  const { connection_bubble_border: border, connection_bubble_opacity: opacity } = settings;

  const vars: Record<string, string> = {};

  if (isBubbleSettingSet(color)) {
    vars[BUBBLE_CSS_VARS.color] = color;
  }

  if (isBubbleSettingSet(size)) {
    vars[BUBBLE_CSS_VARS.size] = `${size}px`;
  }

  if (isBubbleSettingSet(border)) {
    vars[BUBBLE_CSS_VARS.border] = `${border}px`;
  }

  // The fill is the bubble's colour at low alpha. Each half is only overridden when the user set
  // it: a fill alone mixes the theme's own colour, and a colour alone keeps the usual alpha - so
  // setting one never drags the other away from the theme.
  if (isBubbleSettingSet(color)) {
    const fill = bubbleFillColor(color, isBubbleSettingSet(opacity) ? opacity : BUBBLE_DEFAULT_OPACITY);

    if (fill) {
      vars[BUBBLE_CSS_VARS.fill] = fill;
    }
  } else if (isBubbleSettingSet(opacity)) {
    vars[BUBBLE_CSS_VARS.fill] =
      `color-mix(in srgb, var(${BUBBLE_CSS_VARS.color}, ${BUBBLE_DEFAULT_COLOR}) ${opacity}%, transparent)`;
  }

  return vars as CSSProperties;
};
