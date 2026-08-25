export const SPRING_CRISP = {
  type: "spring",
  visualDuration: 0.6,
  bounce: 0.1,
} as const;

export const SPRING_SOFT = {
  type: "spring",
  visualDuration: 0.85,
  bounce: 0.08,
} as const;

export const STAGGER_DELAY = 0.08;

export function prefersReducedMotion(): boolean {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}
