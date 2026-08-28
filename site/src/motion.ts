export const SPRING_CRISP = {
  type: "spring",
  visualDuration: 0.6,
  bounce: 0.1,
} as const;

export function prefersReducedMotion(): boolean {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}
