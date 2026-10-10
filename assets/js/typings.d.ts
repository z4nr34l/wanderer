declare module '*.module.scss' {
  const styles: { [className: string]: string };
  export default styles;
}

declare module 'turndown' {
  export default class TurndownService {
    constructor(options?: Record<string, unknown>);
    turndown(input: string | HTMLElement): string;
  }
}
