/* ═══════════════════════════════════════════
   LUYUAN GE — HACKER PORTFOLIO SCRIPTS
   Feature Set: Matrix, Decryption, Tilt, HUD
   ═══════════════════════════════════════════ */

(function () {
  'use strict';

  gsap.registerPlugin(ScrollTrigger, TextPlugin);

  // ── 1. Matrix Rain with Interaction ──
  function initMatrix() {
    const canvas = document.getElementById('matrixCanvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');

    let width, height, columns;
    const fontSize = 16;
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz$+-*/%=<>!&|^~';
    let drops = [];
    let mouse = { x: -1000, y: -1000 };

    function resize() {
      width = canvas.width = window.innerWidth;
      height = canvas.height = window.innerHeight;
      columns = Math.floor(width / fontSize);
      drops = [];
      for (let i = 0; i < columns; i++) {
        drops[i] = Math.random() * -100;
      }
    }

    function draw() {
      // Fade trail
      ctx.fillStyle = 'rgba(5, 5, 5, 0.05)';
      ctx.fillRect(0, 0, width, height);

      ctx.fillStyle = '#00ffcc';
      ctx.font = fontSize + 'px "JetBrains Mono"';

      for (let i = 0; i < drops.length; i++) {
        const text = chars[Math.floor(Math.random() * chars.length)];
        const x = i * fontSize;
        const y = drops[i] * fontSize;

        // Interaction: Repel drops around mouse
        const dist = Math.abs(x - mouse.x);
        if (dist < 50 && Math.abs(y - mouse.y) < 50) {
           ctx.fillStyle = '#ff00c1'; // Glitch color near mouse
        } else {
           ctx.fillStyle = '#00ffcc';
        }

        ctx.fillText(text, x, y);

        if (y > height && Math.random() > 0.975) {
          drops[i] = 0;
        }
        drops[i]++;
      }
      requestAnimationFrame(draw);
    }

    window.addEventListener('mousemove', (e) => {
      mouse.x = e.clientX;
      mouse.y = e.clientY;
    });

    window.addEventListener('resize', resize);
    resize();
    draw();
  }

  // ── 2. Decryption Text Effect (HyperText) ──
  function initDecryption() {
    const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789$#@%&";
    const targets = document.querySelectorAll('[data-decrypt]');

    const decrypt = (element) => {
      let iterations = 0;
      const originalText = element.getAttribute('data-decrypt');
      // If we've already set the text, don't reset unless we want loop
      // But we just want the effect to run once or on re-entry
      
      const interval = setInterval(() => {
        element.innerText = originalText
          .split("")
          .map((letter, index) => {
            if (index < iterations) {
              return originalText[index];
            }
            return letters[Math.floor(Math.random() * 26)];
          })
          .join("");

        if (iterations >= originalText.length) {
          clearInterval(interval);
        }

        iterations += 1 / 2; // Speed of decoding
      }, 30);
    };

    targets.forEach(target => {
      // Use Intersection Observer to trigger
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            decrypt(entry.target);
            observer.unobserve(entry.target); // Run once
          }
        });
      }, { threshold: 0.5 });
      
      observer.observe(target);
      
      // Also trigger on hover for nav links
      if(target.classList.contains('nav__link')) {
        target.addEventListener('mouseenter', () => decrypt(target));
      }
    });
  }

  // ── 3. 3D Tilt Effect (Vanilla JS) ──
  function initTilt() {
    const cards = document.querySelectorAll('.project-card, .timeline__card, .hero__terminal, .terminal-card');

    cards.forEach(card => {
      card.addEventListener('mousemove', (e) => {
        const rect = card.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;
        
        // Calculate rotation
        const centerX = rect.width / 2;
        const centerY = rect.height / 2;
        
        const rotateX = ((y - centerY) / centerY) * -5; // Max -5deg to 5deg
        const rotateY = ((x - centerX) / centerX) * 5;

        // Apply transform
        card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale3d(1.02, 1.02, 1.02)`;
        
        // Dynamic border/shadow/glare effect could go here
        // Simple glare using box-shadow
        // card.style.boxShadow = `${-rotateY * 2}px ${rotateX * 2}px 20px rgba(0, 255, 204, 0.1)`;
      });

      card.addEventListener('mouseleave', () => {
        card.style.transform = 'perspective(1000px) rotateX(0) rotateY(0) scale3d(1, 1, 1)';
        // card.style.boxShadow = 'none';
      });
    });
  }

  // ── 4. HUD System Monitor ──
  function initHUD() {
    const timeEl = document.getElementById('hudTime');
    const memEl = document.getElementById('hudMem');
    
    // Time
    setInterval(() => {
      const now = new Date();
      timeEl.innerText = now.toISOString().split('T')[1].split('.')[0] + ' UTC';
    }, 1000);

    // Simulated Memory Usage
    setInterval(() => {
      const mem = Math.floor(Math.random() * 20) + 30; // 30-50%
      memEl.innerText = mem + '%';
    }, 2000);
  }

  // ── 5. Standard Animations (GSAP) ──
  function initGSAP() {
     // Typewriter for Hero Name
    gsap.to("#typewriter", {
      duration: 1.5,
      text: "LUYUAN GE",
      delay: 0.5,
      ease: "none"
    });

    // Reveal Sections
    const sections = document.querySelectorAll('.reveal');
    sections.forEach((section) => {
      gsap.to(section, {
        scrollTrigger: {
          trigger: section,
          start: "top 85%",
          toggleActions: "play none none none"
        },
        opacity: 1,
        y: 0,
        duration: 0.8,
        ease: "power2.out"
      });
    });
  }

  // ── Init ──
  document.addEventListener('DOMContentLoaded', () => {
    initMatrix();
    initDecryption();
    initTilt();
    initHUD();
    initGSAP();
    
    // Nav Logic
    const nav = document.getElementById('nav');
    const toggle = document.getElementById('navToggle');
    const mobile = document.getElementById('navMobile');
    
    if (toggle) {
        toggle.addEventListener('click', () => {
            mobile.classList.toggle('nav__mobile--open');
        });
    }

    // Console Easter Egg
    console.log("%c SYSTEM READY // ACCESS GRANTED ", "background: #000; color: #00ffcc; font-size: 14px; padding: 10px; border: 1px solid #00ffcc;");
  });

})();
