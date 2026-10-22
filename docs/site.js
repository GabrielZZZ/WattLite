(() => {
  "use strict";

  const root = document.documentElement;
  const body = document.body;
  const TITLES = {
    en: "WattLite — Live power for macOS and Windows",
    zh: "WattLite — macOS 与 Windows 实时功率监视器",
  };
  const DESCRIPTIONS = {
    en: "A native power monitor for macOS and Windows. Menu bar or taskbar, honest CPU, GPU, battery and disk readings, light and dark themes, and optional signed auto-updates.",
    zh: "macOS 与 Windows 的原生功率监视器。菜单栏或任务栏、诚实的 CPU / GPU / 电池 / 硬盘读数、明暗主题，以及可关闭的签名自动更新。",
  };
  const STORE_KEY = "wattlite-site-lang";

  function currentLang() {
    return root.lang.toLowerCase().startsWith("zh") ? "zh" : "en";
  }

  function translate(lang) {
    root.lang = lang === "zh" ? "zh-CN" : "en";
    document.title = TITLES[lang];

    const description = document.querySelector('meta[name="description"]');
    if (description) description.setAttribute("content", DESCRIPTIONS[lang]);

    root.querySelectorAll("[data-en]").forEach((el) => {
      const value = el.getAttribute(lang === "zh" ? "data-zh" : "data-en");
      if (value !== null) el.innerHTML = value;
    });

    root.querySelectorAll("[data-en-src]").forEach((img) => {
      const src = img.getAttribute(lang === "zh" ? "data-zh-src" : "data-en-src");
      if (src) img.setAttribute("src", src);
    });

    root.querySelectorAll("[data-en-alt]").forEach((img) => {
      const alt = img.getAttribute(lang === "zh" ? "data-zh-alt" : "data-en-alt");
      if (alt) img.setAttribute("alt", alt);
    });

    const enButton = document.getElementById("langEN");
    const zhButton = document.getElementById("langZH");
    if (enButton) enButton.setAttribute("aria-pressed", String(lang === "en"));
    if (zhButton) zhButton.setAttribute("aria-pressed", String(lang === "zh"));

    try {
      localStorage.setItem(STORE_KEY, lang);
    } catch (_) {
      /* storage can be unavailable in private modes */
    }
  }

  function initialLang() {
    const requested = new URLSearchParams(window.location.search).get("lang");
    if (requested === "en" || requested === "zh") return requested;

    try {
      const saved = localStorage.getItem(STORE_KEY);
      if (saved === "en" || saved === "zh") return saved;
    } catch (_) {
      /* ignore */
    }

    return (navigator.language || "en").toLowerCase().startsWith("zh") ? "zh" : "en";
  }

  const enButton = document.getElementById("langEN");
  const zhButton = document.getElementById("langZH");
  if (enButton) enButton.addEventListener("click", () => translate("en"));
  if (zhButton) zhButton.addEventListener("click", () => translate("zh"));
  translate(initialLang());

  /* Which build to recommend on the download buttons. */
  const platform = (navigator.userAgentData && navigator.userAgentData.platform) ||
    navigator.platform ||
    "";
  const userAgent = navigator.userAgent || "";
  const macLike = /mac/i.test(platform) || /Macintosh|Mac OS X/i.test(userAgent);
  // iPadOS reports MacIntel; a touch Mac should not be offered the desktop build.
  const touchMac = macLike && navigator.maxTouchPoints > 1;
  if (macLike && !touchMac) {
    body.classList.add("is-mac");
  } else if (/win/i.test(platform) || /Windows/i.test(userAgent)) {
    body.classList.add("is-win");
  }

  /* Download line: official GitHub or the mainland-China proxy. */
  const GITHUB_RELEASE = "https://github.com/GabrielZZZ/WattLite/releases/download/";
  const MIRROR_PREFIX = "https://ghfast.top/";
  const releaseLinks = Array.from(
    document.querySelectorAll(`a[href^="${GITHUB_RELEASE}"]`)
  );
  const lineButtons = Array.from(document.querySelectorAll(".line-btn"));
  const lineHints = Array.from(document.querySelectorAll(".line-hint"));

  releaseLinks.forEach((link) => {
    const href = link.getAttribute("href");
    if (!href) return;
    link.dataset.officialHref = href;
    link.dataset.mirrorHref = MIRROR_PREFIX + href;
  });

  function setDownloadLine(line) {
    const useMirror = line === "mirror";
    releaseLinks.forEach((link) => {
      const target = useMirror ? link.dataset.mirrorHref : link.dataset.officialHref;
      if (target) link.setAttribute("href", target);
    });
    lineButtons.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.line === line));
    });
    lineHints.forEach((hint) => {
      hint.hidden = hint.dataset.lineHint !== line;
    });
  }

  lineButtons.forEach((button) => {
    button.addEventListener("click", () => setDownloadLine(button.dataset.line || "official"));
  });

  document.querySelectorAll("[data-mirror-jump]").forEach((link) => {
    link.addEventListener("click", () => setDownloadLine("mirror"));
  });

  setDownloadLine(
    new URLSearchParams(window.location.search).get("line") === "mirror" ? "mirror" : "official"
  );

  /* Checksum copy. */
  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }

    return new Promise((resolve, reject) => {
      const area = document.createElement("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.top = "-1000px";
      area.style.opacity = "0";
      document.body.appendChild(area);
      area.select();

      try {
        if (document.execCommand("copy")) resolve();
        else reject(new Error("copy command failed"));
      } catch (error) {
        reject(error);
      } finally {
        area.remove();
      }
    });
  }

  root.querySelectorAll(".copy-btn").forEach((button) => {
    button.addEventListener("click", () => {
      const hash = button.getAttribute("data-copy");
      if (!hash) return;
      const lang = currentLang();
      let timer = 0;

      copyText(hash)
        .then(() => {
          button.textContent = lang === "zh" ? "已复制" : "Copied";
          button.classList.add("copied");
        })
        .catch(() => {
          button.textContent = lang === "zh" ? "复制失败" : "Copy failed";
        })
        .finally(() => {
          window.clearTimeout(timer);
          timer = window.setTimeout(() => {
            button.textContent = currentLang() === "zh" ? "复制" : "Copy";
            button.classList.remove("copied");
          }, 1800);
        });
    });
  });

  /* Header gets a background once the page scrolls. */
  const header = document.getElementById("siteHeader");
  if (header) {
    const updateHeader = () => header.classList.toggle("scrolled", window.scrollY > 8);
    updateHeader();
    window.addEventListener("scroll", updateHeader, { passive: true });
  }

  /* Reveal sections as they enter the viewport. */
  const reveals = root.querySelectorAll(".reveal");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  if (!("IntersectionObserver" in window) || reduceMotion) {
    reveals.forEach((el) => el.classList.add("in"));
  } else {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("in");
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.06 }
    );

    reveals.forEach((el) => observer.observe(el));
  }
})();
