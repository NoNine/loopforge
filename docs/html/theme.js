const storageKey = "docs-browser-theme";

export function initTheme(button) {
  const saved = localStorage.getItem(storageKey);
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  setTheme(saved || (prefersDark ? "dark" : "light"));

  button?.addEventListener("click", () => {
    const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    localStorage.setItem(storageKey, next);
    setTheme(next);
  });
}

function setTheme(theme) {
  document.documentElement.dataset.theme = theme;
}
