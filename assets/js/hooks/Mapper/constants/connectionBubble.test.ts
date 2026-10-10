import { bubbleCssVars, isBubbleSettingSet } from './connectionBubble';

describe('the bubble on a bubbled connection end', () => {
  it('follows the theme for anything left empty, whichever way it was saved', () => {
    // empty and zero are what older versions saved, null is what a reset saves now
    expect(isBubbleSettingSet('')).toBe(false);
    expect(isBubbleSettingSet(0)).toBe(false);
    expect(isBubbleSettingSet(null)).toBe(false);
    expect(isBubbleSettingSet(undefined)).toBe(false);

    expect(
      bubbleCssVars({
        connection_bubble_color: '',
        connection_bubble_size: 0,
        connection_bubble_border: null,
        connection_bubble_opacity: undefined,
      }),
    ).toEqual({});
  });

  it('writes only what the user set', () => {
    expect(bubbleCssVars({ connection_bubble_size: 20 })).toEqual({ '--rf-edge-bubble-size': '20px' });
    expect(bubbleCssVars({ connection_bubble_border: 3 })).toEqual({ '--rf-edge-bubble-border': '3px' });
  });

  it("mixes a fill set on its own with the theme's colour, not a hard-coded one", () => {
    const vars = bubbleCssVars({ connection_bubble_opacity: 40 }) as Record<string, string>;

    expect(vars['--rf-edge-bubble']).toBeUndefined();
    expect(vars['--rf-edge-bubble-fill']).toContain('var(--rf-edge-bubble');
    expect(vars['--rf-edge-bubble-fill']).toContain('40%');
  });

  it('keeps the usual alpha when only the colour is set', () => {
    const vars = bubbleCssVars({ connection_bubble_color: '#ff0000' }) as Record<string, string>;

    expect(vars['--rf-edge-bubble']).toBe('#ff0000');
    expect(vars['--rf-edge-bubble-fill']).toBe('rgba(255, 0, 0, 0.18)');
  });

  it('uses both halves when both are set', () => {
    const vars = bubbleCssVars({
      connection_bubble_color: '#00ff00',
      connection_bubble_opacity: 50,
    }) as Record<string, string>;

    expect(vars['--rf-edge-bubble-fill']).toBe('rgba(0, 255, 0, 0.5)');
  });
});
