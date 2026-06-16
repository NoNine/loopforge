import { renderMarkdown } from "./markdown.js";
import { initTheme } from "./theme.js";

const params = new URLSearchParams(window.location.search);
const path = params.get("path") || "";
const content = document.querySelector("#content");
const docTitle = document.querySelector("#docTitle");
const docPath = document.querySelector("#docPath");

initTheme(document.querySelector("#themeToggle"));
loadDoc();

async function loadDoc() {
  if (!path) {
    showError("Missing document path.");
    return;
  }

  docPath.textContent = path;
  docTitle.textContent = titleFromPath(path);

  try {
    const response = await fetch(`/api/doc?path=${encodeURIComponent(path)}`);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    docTitle.textContent = data.title || titleFromPath(data.path);
    docPath.textContent = data.path;
    content.innerHTML = renderMarkdown(data.content);
  } catch (error) {
    showError(`Failed to load document: ${error.message}`);
  }
}

function titleFromPath(value) {
  return value
    .split("/")
    .pop()
    .replace(/\.md$/i, "")
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function showError(message) {
  docTitle.textContent = "Document unavailable";
  content.innerHTML = `<p class="empty">${escapeHtml(message)}</p>`;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
