/* ═══════════════════════════════════════════
   LUYUAN GE — PORTFOLIO SCRIPTS
   ═══════════════════════════════════════════ */

(function () {
  'use strict';

  // ── Dot-Grid Canvas Background ──
  function initCanvas() {
    const canvas = document.getElementById('heroCanvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    let width, height, cols, rows;
    const spacing = 32;
    const dotBase = 1;
    let mouse = { x: -1000, y: -1000 };
    let animId;

    function resize() {
      width = canvas.width = canvas.offsetWidth;
      height = canvas.height = canvas.offsetHeight;
      cols = Math.ceil(width / spacing) + 1;
      rows = Math.ceil(height / spacing) + 1;
    }

    function draw() {
      ctx.clearRect(0, 0, width, height);
      const radius = 180;

      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
          const x = c * spacing;
          const y = r * spacing;
          const dx = mouse.x - x;
          const dy = mouse.y - y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          const proximity = Math.max(0, 1 - dist / radius);

          const size = dotBase + proximity * 2.5;
          const alpha = 0.12 + proximity * 0.55;

          ctx.beginPath();
          ctx.arc(x, y, size, 0, Math.PI * 2);

          if (proximity > 0.01) {
            ctx.fillStyle = `rgba(0, 212, 170, ${alpha})`;
          } else {
            ctx.fillStyle = `rgba(200, 200, 208, ${alpha * 0.7})`;
          }
          ctx.fill();
        }
      }

      animId = requestAnimationFrame(draw);
    }

    canvas.addEventListener('mousemove', (e) => {
      const rect = canvas.getBoundingClientRect();
      mouse.x = e.clientX - rect.left;
      mouse.y = e.clientY - rect.top;
    });

    canvas.addEventListener('mouseleave', () => {
      mouse.x = -1000;
      mouse.y = -1000;
    });

    // Touch support
    canvas.addEventListener('touchmove', (e) => {
      const rect = canvas.getBoundingClientRect();
      mouse.x = e.touches[0].clientX - rect.left;
      mouse.y = e.touches[0].clientY - rect.top;
    }, { passive: true });

    window.addEventListener('resize', resize);
    resize();
    draw();
  }

  // ── Scroll Reveal (IntersectionObserver) ──
  function initReveal() {
    const els = document.querySelectorAll('.reveal');
    if (!els.length) return;

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add('reveal--visible');
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.15, rootMargin: '0px 0px -40px 0px' }
    );

    els.forEach((el) => observer.observe(el));
  }

  // ── Active Nav Tracking ──
  function initNavTracking() {
    const sections = document.querySelectorAll('.section, .hero');
    const links = document.querySelectorAll('.nav__link');
    if (!sections.length || !links.length) return;

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const id = entry.target.id;
            links.forEach((link) => {
              link.classList.toggle(
                'nav__link--active',
                link.getAttribute('data-section') === id
              );
            });
          }
        });
      },
      { threshold: 0.2, rootMargin: '-64px 0px -40% 0px' }
    );

    sections.forEach((s) => observer.observe(s));
  }

  // ── Scrolled Nav Style ──
  function initNavScroll() {
    const nav = document.getElementById('nav');
    if (!nav) return;

    let ticking = false;
    window.addEventListener('scroll', () => {
      if (!ticking) {
        requestAnimationFrame(() => {
          nav.classList.toggle('nav--scrolled', window.scrollY > 40);
          ticking = false;
        });
        ticking = true;
      }
    });
  }

  // ── Mobile Menu Toggle ──
  function initMobileMenu() {
    const toggle = document.getElementById('navToggle');
    const mobile = document.getElementById('navMobile');
    if (!toggle || !mobile) return;

    toggle.addEventListener('click', () => {
      toggle.classList.toggle('nav__toggle--open');
      mobile.classList.toggle('nav__mobile--open');
    });

    // Close on link click
    mobile.querySelectorAll('.nav__mobile-link').forEach((link) => {
      link.addEventListener('click', () => {
        toggle.classList.remove('nav__toggle--open');
        mobile.classList.remove('nav__mobile--open');
      });
    });
  }

  // ── Init ──
  document.addEventListener('DOMContentLoaded', () => {
    initCanvas();
    initReveal();
    initNavTracking();
    initNavScroll();
    initMobileMenu();
  });
})();
