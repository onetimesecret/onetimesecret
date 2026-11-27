// src/shared/composables/useBackdropClose.ts

/**
 * Close a hand-rolled modal when the user clicks its dimmed backdrop.
 *
 * Bind both handlers on the overlay element. A click counts only when the
 * press also started on the overlay: a drag that starts in a field inside
 * the panel and is released over the backdrop fires `click` on the overlay
 * (the nearest common ancestor), and must not close the dialog or discard
 * what was typed.
 *
 * @param close - called for a backdrop click; it decides whether closing is
 *   allowed right now (for example, not while a request is running).
 */
export function useBackdropClose(close: () => void) {
  let pressedOnBackdrop = false;

  const onBackdropMousedown = (event: MouseEvent) => {
    pressedOnBackdrop = event.target === event.currentTarget;
  };

  const onBackdropClick = (event: MouseEvent) => {
    const startedHere = pressedOnBackdrop;
    pressedOnBackdrop = false;
    if (startedHere && event.target === event.currentTarget) close();
  };

  return { onBackdropMousedown, onBackdropClick };
}
