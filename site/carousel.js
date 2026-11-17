(() => {
  const root = document.querySelector("[data-carousel]");
  if (!root) return;

  const track = root.querySelector("[data-carousel-track]");
  const status = root.querySelector("[data-carousel-status]");
  const progress = root.querySelector("[data-carousel-progress]");
  const slides = Array.from(root.querySelectorAll("[data-slide]"));
  if (!track || !status || !progress || slides.length < 2) return;

  const segments = Array.from(progress.children);
  if (segments.length !== slides.length) return;

  const PROGRESS_ANIMATION = "slide-progress";
  const SCROLL_SETTLE_MS = 120;
  const DRAG_START_PX = 4;
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  let index = 0;
  let settleTimer = 0;
  let isFocused = false;
  let drag = null;

  const wrap = (i) => (i + slides.length) % slides.length;
  const clamp = (i) => Math.min(Math.max(i, 0), slides.length - 1);
  const slideLeft = (i) => i * track.clientWidth;

  function render(shouldAnnounce) {
    slides.forEach((slide, i) => {
      slide.inert = i !== index;
    });
    segments.forEach((segment, i) => {
      segment.classList.toggle("is-done", i < index);
      segment.classList.toggle("is-active", i === index);
    });
    if (shouldAnnounce) {
      const title = slides[index].dataset.title || "";
      status.textContent = `${title}, ${index + 1} of ${slides.length}`;
    }
  }

  function goTo(target, shouldAnnounce) {
    index = target;
    render(shouldAnnounce);
    track.scrollTo({
      left: slideLeft(index),
      behavior: reducedMotion.matches ? "auto" : "smooth",
    });
  }

  function syncAutoplay() {
    root.dataset.autoplay = reducedMotion.matches ? "off" : "on";
    root.toggleAttribute("data-paused", isFocused || drag !== null || document.hidden);
  }

  function settleFreeScroll() {
    root.removeAttribute("data-free-scroll");
  }

  track.addEventListener(
    "scroll",
    () => {
      window.clearTimeout(settleTimer);
      settleTimer = window.setTimeout(() => {
        if (drag) return;
        settleFreeScroll();
        const settled = clamp(Math.round(track.scrollLeft / track.clientWidth));
        if (settled === index) return;
        index = settled;
        render(true);
      }, SCROLL_SETTLE_MS);
    },
    { passive: true }
  );

  track.addEventListener("pointerdown", (event) => {
    if (event.pointerType === "touch" || event.button !== 0) return;
    drag = { id: event.pointerId, startX: event.clientX, startLeft: track.scrollLeft, hasMoved: false };
    syncAutoplay();
  });

  track.addEventListener("pointermove", (event) => {
    if (!drag || event.pointerId !== drag.id) return;
    const dx = event.clientX - drag.startX;
    if (!drag.hasMoved) {
      if (Math.abs(dx) < DRAG_START_PX) return;
      drag.hasMoved = true;
      root.setAttribute("data-dragging", "");
      root.setAttribute("data-free-scroll", "");
      track.setPointerCapture(drag.id);
    }
    track.scrollLeft = drag.startLeft - dx;
  });

  function endDrag(event) {
    if (!drag || event.pointerId !== drag.id) return;
    const { startX, hasMoved } = drag;
    drag = null;
    root.removeAttribute("data-dragging");
    syncAutoplay();
    if (!hasMoved) return;
    const dx = event.clientX - startX;
    const threshold = Math.min(80, track.clientWidth * 0.12);
    const step = dx < -threshold ? 1 : dx > threshold ? -1 : 0;
    const target = clamp(index + step);
    if (Math.abs(track.scrollLeft - slideLeft(target)) < 1) settleFreeScroll();
    goTo(target, step !== 0);
  }

  progress.addEventListener("animationend", (event) => {
    if (event.animationName === PROGRESS_ANIMATION) goTo(wrap(index + 1), false);
  });

  track.addEventListener("pointerup", endDrag);
  track.addEventListener("pointercancel", endDrag);

  root.addEventListener("keydown", (event) => {
    const keyTargets = {
      ArrowLeft: clamp(index - 1),
      ArrowRight: clamp(index + 1),
      Home: 0,
      End: slides.length - 1,
    };
    if (!(event.key in keyTargets) || event.altKey || event.metaKey || event.ctrlKey) return;
    event.preventDefault();
    goTo(keyTargets[event.key], true);
  });

  // A mouse click or drag focuses the slider too; only keyboard focus should hold autoplay.
  root.addEventListener("focusin", (event) => {
    isFocused = event.target.matches(":focus-visible");
    syncAutoplay();
  });
  root.addEventListener("focusout", (event) => {
    if (root.contains(event.relatedTarget)) return;
    isFocused = false;
    syncAutoplay();
  });
  document.addEventListener("visibilitychange", syncAutoplay);
  reducedMotion.addEventListener("change", syncAutoplay);

  render(false);
  syncAutoplay();
})();
