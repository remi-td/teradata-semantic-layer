/* Teradata Semantic Catalog — landing page enhancements.
 * Zero dependencies. Two small behaviours: active-section highlight
 * in the sticky nav, and a subtle reveal-on-scroll for cards. */
(function () {
  'use strict';

  // ---------- Active section highlight in the sticky nav -----------
  const navLinks = Array.from(document.querySelectorAll('.top-nav a[href^="#"]'));
  const sections = navLinks
    .map(a => document.querySelector(a.getAttribute('href')))
    .filter(Boolean);

  if ('IntersectionObserver' in window && sections.length) {
    const active = new Map();
    const io = new IntersectionObserver(entries => {
      entries.forEach(e => active.set(e.target.id, e.isIntersecting ? e.intersectionRatio : 0));
      let best = null; let bestRatio = 0;
      active.forEach((r, id) => { if (r > bestRatio) { bestRatio = r; best = id; } });
      navLinks.forEach(a => a.classList.toggle(
        'is-active',
        best != null && a.getAttribute('href') === '#' + best
      ));
    }, { rootMargin: '-40% 0px -50% 0px', threshold: [0.0, 0.25, 0.5, 0.75, 1.0] });
    sections.forEach(s => io.observe(s));
  }

  // ---------- Reveal on scroll (cards fade/slide in) ---------------
  const reveal = document.querySelectorAll(
    '.problem-card, .principle, .onto-card, .sec-card, .start-step, .demo-step'
  );
  reveal.forEach(el => el.classList.add('reveal'));
  if ('IntersectionObserver' in window) {
    const io2 = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (e.isIntersecting) {
          e.target.classList.add('is-visible');
          io2.unobserve(e.target);
        }
      });
    }, { threshold: 0.08 });
    reveal.forEach(el => io2.observe(el));
  } else {
    reveal.forEach(el => el.classList.add('is-visible'));
  }
})();
