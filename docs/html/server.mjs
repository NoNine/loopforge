#!/usr/bin/env node
import { createServer } from "node:http";
import { createReadStream, promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const htmlDir = path.dirname(fileURLToPath(import.meta.url));
const docsDir = path.resolve(htmlDir, "..");
const host = process.env.HOST || "127.0.0.1";
const port = Number(process.env.PORT || 4173);

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8"
};

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", `http://${request.headers.host || "localhost"}`);

    if (url.pathname === "/api/docs") {
      await sendJson(response, await listDocs());
      return;
    }

    if (url.pathname === "/api/doc") {
      await sendJson(response, await readDoc(url.searchParams.get("path") || ""));
      return;
    }

    await serveStatic(url.pathname, response);
  } catch (error) {
    const status = error.status || 500;
    await sendJson(response, { error: error.message || "Server error" }, status);
  }
});

server.listen(port, host, () => {
  console.log(`Docs browser listening on http://${host}:${port}/`);
});

async function listDocs() {
  const files = await walk(docsDir);
  const docs = [];

  for (const file of files) {
    const rel = relativeDocPath(file);
    if (!rel || rel.startsWith("html/") || !rel.endsWith(".md")) continue;
    const stat = await fs.stat(file);
    const content = await fs.readFile(file, "utf8");
    docs.push({
      path: rel,
      title: titleFromMarkdown(content, rel),
      size: stat.size,
      mtime: stat.mtime.toISOString()
    });
  }

  return docs.sort((a, b) => a.path.localeCompare(b.path));
}

async function readDoc(requestedPath) {
  const file = resolveDocPath(requestedPath);
  const content = await fs.readFile(file, "utf8");
  return {
    path: relativeDocPath(file),
    title: titleFromMarkdown(content, requestedPath),
    content
  };
}

async function walk(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...await walk(full));
    } else if (entry.isFile()) {
      files.push(full);
    }
  }
  return files;
}

function resolveDocPath(requestedPath) {
  if (!requestedPath || requestedPath.includes("\0")) {
    throw httpError(400, "Missing document path.");
  }
  const normalized = path.normalize(requestedPath).replace(/^(\.\.[/\\])+/, "");
  const file = path.resolve(docsDir, normalized);
  if (!file.startsWith(`${docsDir}${path.sep}`) || path.extname(file) !== ".md") {
    throw httpError(400, "Document path is outside docs or is not Markdown.");
  }
  return file;
}

function relativeDocPath(file) {
  return path.relative(docsDir, file).split(path.sep).join("/");
}

async function serveStatic(urlPath, response) {
  const cleanPath = decodeURIComponent(urlPath === "/" ? "/index.html" : urlPath);
  const file = path.resolve(htmlDir, `.${path.normalize(cleanPath)}`);
  if (!file.startsWith(`${htmlDir}${path.sep}`)) {
    throw httpError(403, "Forbidden.");
  }

  const stat = await fs.stat(file).catch(() => null);
  if (!stat?.isFile()) {
    throw httpError(404, "Not found.");
  }

  response.writeHead(200, {
    "Content-Type": mimeTypes[path.extname(file)] || "application/octet-stream",
    "Cache-Control": "no-store"
  });
  createReadStream(file).pipe(response);
}

async function sendJson(response, data, status = 200) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(JSON.stringify(data));
}

function titleFromMarkdown(content, fallbackPath) {
  const match = content.match(/^#\s+(.+)$/m);
  if (match) return match[1].trim();
  return path.basename(fallbackPath, ".md").replace(/[-_]+/g, " ");
}

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}
