import { initTheme } from "./theme.js";

const list = document.querySelector("#docList");
const empty = document.querySelector("#emptyState");
const filterInput = document.querySelector("#filterInput");
const stats = document.querySelector("#stats");

let docs = [];

initTheme(document.querySelector("#themeToggle"));
loadDocs();

filterInput.addEventListener("input", () => renderList());

async function loadDocs() {
  try {
    const response = await fetch("/api/docs");
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    docs = await response.json();
    renderList();
  } catch (error) {
    list.innerHTML = `<p class="empty">Failed to load docs: ${escapeHtml(error.message)}</p>`;
    stats.textContent = "Unavailable";
  }
}

function renderList() {
  const query = filterInput.value.trim().toLowerCase();
  const filtered = docs.filter((doc) => {
    const haystack = `${doc.path} ${doc.title}`.toLowerCase();
    return haystack.includes(query);
  });

  stats.textContent = `${filtered.length} of ${docs.length} docs`;
  empty.hidden = filtered.length !== 0;
  list.innerHTML = filtered.map(card).join("");
}

function card(doc) {
  const href = `./view.html?path=${encodeURIComponent(doc.path)}`;
  return `
    <a class="doc-card" href="${href}" target="_blank" rel="noopener noreferrer">
      <div class="doc-title">
        <strong>${escapeHtml(doc.title)}</strong>
        <span class="open-label">Open</span>
      </div>
      <p class="path">${escapeHtml(doc.path)}</p>
      <div class="meta">
        <span>${formatBytes(doc.size)}</span>
        <span>${formatDate(doc.mtime)}</span>
      </div>
    </a>
  `;
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function formatDate(value) {
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
