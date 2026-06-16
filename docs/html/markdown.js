const blockToken = "\u0000CODE";

export function renderMarkdown(markdown) {
  const codeBlocks = [];
  let text = markdown.replace(/\r\n?/g, "\n");

  text = text.replace(/```([^\n`]*)\n([\s\S]*?)```/g, (_, lang, code) => {
    const index = codeBlocks.push({ lang: lang.trim(), code }) - 1;
    return `${blockToken}${index}\u0000`;
  });

  const lines = text.split("\n");
  const html = [];
  let paragraph = [];
  let list = null;

  const flushParagraph = () => {
    if (paragraph.length === 0) return;
    html.push(`<p>${inline(paragraph.join(" "))}</p>`);
    paragraph = [];
  };

  const closeList = () => {
    if (!list) return;
    html.push(`</${list}>`);
    list = null;
  };

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const trimmed = line.trim();

    if (!trimmed) {
      flushParagraph();
      closeList();
      continue;
    }

    const codeMatch = trimmed.match(new RegExp(`^${blockToken}(\\d+)\\u0000$`));
    if (codeMatch) {
      flushParagraph();
      closeList();
      const block = codeBlocks[Number(codeMatch[1])];
      const lang = block.lang ? ` data-lang="${escapeHtml(block.lang)}"` : "";
      html.push(`<pre${lang}><code>${escapeHtml(block.code)}</code></pre>`);
      continue;
    }

    if (/^---+$/.test(trimmed)) {
      flushParagraph();
      closeList();
      html.push("<hr>");
      continue;
    }

    const heading = trimmed.match(/^(#{1,6})\s+(.+)$/);
    if (heading) {
      flushParagraph();
      closeList();
      const level = heading[1].length;
      html.push(`<h${level}>${inline(heading[2])}</h${level}>`);
      continue;
    }

    if (isTableStart(lines, i)) {
      flushParagraph();
      closeList();
      const tableLines = [];
      while (i < lines.length && lines[i].trim().startsWith("|")) {
        tableLines.push(lines[i].trim());
        i += 1;
      }
      i -= 1;
      html.push(renderTable(tableLines));
      continue;
    }

    const quote = trimmed.match(/^>\s?(.*)$/);
    if (quote) {
      flushParagraph();
      closeList();
      html.push(`<blockquote><p>${inline(quote[1])}</p></blockquote>`);
      continue;
    }

    const unordered = trimmed.match(/^[-*]\s+(.+)$/);
    if (unordered) {
      flushParagraph();
      if (list !== "ul") {
        closeList();
        list = "ul";
        html.push("<ul>");
      }
      html.push(`<li>${inline(unordered[1])}</li>`);
      continue;
    }

    const ordered = trimmed.match(/^\d+\.\s+(.+)$/);
    if (ordered) {
      flushParagraph();
      if (list !== "ol") {
        closeList();
        list = "ol";
        html.push("<ol>");
      }
      html.push(`<li>${inline(ordered[1])}</li>`);
      continue;
    }

    closeList();
    paragraph.push(trimmed);
  }

  flushParagraph();
  closeList();
  return html.join("\n");
}

function isTableStart(lines, index) {
  const current = lines[index]?.trim() || "";
  const next = lines[index + 1]?.trim() || "";
  return current.startsWith("|") && /^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$/.test(next);
}

function renderTable(lines) {
  const rows = lines
    .filter((_, index) => index !== 1)
    .map((line) => splitTableRow(line));

  const header = rows[0] || [];
  const body = rows.slice(1);

  const headHtml = `<thead><tr>${header.map((cell) => `<th>${inline(cell)}</th>`).join("")}</tr></thead>`;
  const bodyHtml = `<tbody>${body.map((row) => `<tr>${row.map((cell) => `<td>${inline(cell)}</td>`).join("")}</tr>`).join("")}</tbody>`;
  return `<div class="table-wrap"><table>${headHtml}${bodyHtml}</table></div>`;
}

function splitTableRow(line) {
  return line
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());
}

function inline(value) {
  let output = escapeHtml(value);
  const code = [];
  output = output.replace(/`([^`]+)`/g, (_, content) => {
    const index = code.push(content) - 1;
    return `\u0000INLINE${index}\u0000`;
  });
  output = output.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, text, href) => {
    const safeHref = String(href).trim();
    if (/^(javascript|data):/i.test(safeHref)) return text;
    return `<a href="${escapeAttribute(safeHref)}" target="_blank" rel="noopener noreferrer">${text}</a>`;
  });
  output = output.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  output = output.replace(/\*([^*]+)\*/g, "<em>$1</em>");
  output = output.replace(/\u0000INLINE(\d+)\u0000/g, (_, index) => `<code>${code[Number(index)]}</code>`);
  return output;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function escapeAttribute(value) {
  return escapeHtml(value).replace(/'/g, "&#39;");
}
