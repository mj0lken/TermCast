(() => {
  const root = document.querySelector("[data-carousel]");
  if (!root) return;

  const track = root.querySelector("[data-carousel-track]");
  const controls = root.querySelector("[data-carousel-controls]");
  const prevBtn = root.querySelector("[data-carousel-prev]");
  const nextBtn = root.querySelector("[data-carousel-next]");
  const toggleBtn = root.querySelector("[data-carousel-toggle]");
  const status = root.querySelector("[data-carousel-status]");
  const slides = Array.from(root.querySelectorAll("[data-slide]"));
  const dots = Array.from(root.querySelectorAll("[data-carousel-dot]"));

  if (!track || !controls || !prevBtn || !nextBtn || !toggleBtn || !status) return;
  if (slides.length < 2 || dots.length !== slides.length) return;

  const PROGRESS_ANIMATION = "carousel-progress";
  const SCROLL_SETTLE_MS = 120;
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  let index = 0;
  let settleTimer = 0;
  let isHovered = false;
  let isFocused = false;
  let isUserPaused = false;

  const wrap = (i) => (i + slides.length) % slides.length;

  function render(shouldAnnounce) {
    slides.forEach((slide, i) => {
      slide.inert = i !== index;
    });
    dots.forEach((dot, i) => {
      if (i === index) dot.setAttribute("aria-current", "true");
      else dot.removeAttribute("aria-current");
    });
    if (shouldAnnounce) {
      const title = slides[index].dataset.title || "";
      status.textContent = `${title}, ${index + 1} of ${slides.length}`;
    }
  }

  function goTo(target, shouldAnnounce) {
    index = wrap(target);
    render(shouldAnnounce);
    track.scrollTo({
      left: index * track.clientWidth,
      behavior: reducedMotion.matches ? "auto" : "smooth",
    });
  }

  function syncPlayback() {
    const canAutoplay = !reducedMotion.matches && !isUserPaused;
    root.dataset.autoplay = canAutoplay ? "on" : "off";
    root.toggleAttribute("data-paused", isHovered || isFocused || document.hidden);

    toggleBtn.hidden = reducedMotion.matches;
    toggleBtn.setAttribute("aria-label", isUserPaused ? "Play slideshow" : "Pause slideshow");
    toggleBtn.dataset.state = isUserPaused ? "paused" : "playing";
  }

  track.addEventListener(
    "scroll",
    () => {
      window.clearTimeout(settleTimer);
      settleTimer = window.setTimeout(() => {
        const settled = wrap(Math.round(track.scrollLeft / track.clientWidth));
        if (settled === index) return;
        index = settled;
        render(true);
      }, SCROLL_SETTLE_MS);
    },
    { passive: true }
  );

  prevBtn.addEventListener("click", () => goTo(index - 1, true));
  nextBtn.addEventListener("click", () => goTo(index + 1, true));
  dots.forEach((dot, i) => dot.addEventListener("click", () => goTo(i, true)));

  toggleBtn.addEventListener("click", () => {
    isUserPaused = !isUserPaused;
    syncPlayback();
  });

  controls.addEventListener("animationend", (event) => {
    if (event.animationName === PROGRESS_ANIMATION) goTo(index + 1, false);
  });

  root.addEventListener("keydown", (event) => {
    const keyTargets = {
      ArrowLeft: index - 1,
      ArrowRight: index + 1,
      Home: 0,
      End: slides.length - 1,
    };
    if (!(event.key in keyTargets) || event.altKey || event.metaKey || event.ctrlKey) return;
    event.preventDefault();
    goTo(keyTargets[event.key], true);
  });

  root.addEventListener("pointerenter", () => {
    isHovered = true;
    syncPlayback();
  });
  root.addEventListener("pointerleave", () => {
    isHovered = false;
    syncPlayback();
  });
  root.addEventListener("focusin", () => {
    isFocused = true;
    syncPlayback();
  });
  root.addEventListener("focusout", (event) => {
    if (root.contains(event.relatedTarget)) return;
    isFocused = false;
    syncPlayback();
  });
  document.addEventListener("visibilitychange", syncPlayback);
  reducedMotion.addEventListener("change", syncPlayback);

  controls.hidden = false;
  render(false);
  syncPlayback();
})();
