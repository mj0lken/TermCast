#!/usr/bin/env node
// Rebrand user-facing Tinycast strings in Xcode String Catalogs to Termcast, and optionally
// 3-way merge conflicted catalogs during upstream syncs so Swift call sites stay conflict-free.
"use strict";

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const CATALOGS = [
  "Tinycast/Resources/Localizable.xcstrings",
  "Tinycast/Resources/InfoPlist.xcstrings",
];

const resolveConflicts = process.argv.includes("--resolve-conflicts");

function git(args) {
  return execFileSync("git", args, { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
}

function readStage(stage, relPath) {
  try {
    return JSON.parse(git(["show", `:${stage}:${relPath}`]));
  } catch {
    return null;
  }
}

function mergeConflictedCatalog(relPath) {
  const base = readStage(1, relPath) ?? { strings: {} };
  const ours = readStage(2, relPath);
  const theirs = readStage(3, relPath);
  if (!ours || !theirs) return false;

  const mergedStrings = { ...theirs.strings };
  for (const [key, entry] of Object.entries(ours.strings ?? {})) {
    if (!(key in (base.strings ?? {})) && !(key in mergedStrings)) {
      mergedStrings[key] = entry;
    }
  }
  const sortedKeys = Object.keys(mergedStrings).sort();
  const ordered = {};
  for (const k of sortedKeys) ordered[k] = mergedStrings[k];
  const merged = { ...theirs, strings: ordered };
  fs.writeFileSync(path.join(ROOT, relPath), formatXcodeJSON(merged) + "\n");
  git(["add", relPath]);
  return true;
}

function rebrandText(text) {
  return text
    .replace(/tinycast:\/\//g, "termcast://")
    .replace(/Tinycast(?![A-Za-z])/g, "Termcast");
}

function rebrandNode(node) {
  if (!node || typeof node !== "object") return;
  if (node.stringUnit && typeof node.stringUnit.value === "string") {
    node.stringUnit.value = rebrandText(node.stringUnit.value);
  }
  for (const cases of Object.values(node.variations ?? {})) {
    for (const child of Object.values(cases ?? {})) rebrandNode(child);
  }
  for (const child of Object.values(node.substitutions ?? {})) {
    rebrandNode(child);
  }
}

function sortKeys(obj) {
  const out = {};
  for (const k of Object.keys(obj).sort()) out[k] = obj[k];
  return out;
}

function formatXcodeJSON(val, indent = 0) {
  const pad = "  ".repeat(indent);
  if (Array.isArray(val)) {
    if (val.length === 0) return "[\n\n" + pad + "]";
    const items = val.map((v) => "  ".repeat(indent + 1) + formatXcodeJSON(v, indent + 1));
    return "[\n" + items.join(",\n") + "\n" + pad + "]";
  }
  if (val && typeof val === "object") {
    const keys = Object.keys(val);
    if (keys.length === 0) return "{\n\n" + pad + "}";
    const lines = keys.map(
      (k) => "  ".repeat(indent + 1) + JSON.stringify(k) + " : " + formatXcodeJSON(val[k], indent + 1)
    );
    return "{\n" + lines.join(",\n") + "\n" + pad + "}";
  }
  return JSON.stringify(val);
}

if (resolveConflicts) {
  const unmerged = new Set(
    git(["diff", "--name-only", "--diff-filter=U"])
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean)
  );
  for (const relPath of CATALOGS) {
    if (unmerged.has(relPath)) {
      mergeConflictedCatalog(relPath);
    }
  }
}

let updatedEntries = 0;
for (const relPath of CATALOGS) {
  const fullPath = path.join(ROOT, relPath);
  const raw = fs.readFileSync(fullPath, "utf8");
  const trailingNewline = raw.endsWith("\n") ? "\n" : "";
  const catalog = JSON.parse(raw);

  for (const [key, entry] of Object.entries(catalog.strings ?? {})) {
    if (!entry || typeof entry !== "object") continue;
    if (/Tinycast(?![A-Za-z])|tinycast:\/\//.test(key)) {
      entry.localizations = entry.localizations ?? {};
      if (!entry.localizations.en) {
        entry.localizations.en = {
          stringUnit: {
            state: "translated",
            value: rebrandText(key),
          },
        };
        entry.localizations = sortKeys(entry.localizations);
      }
      updatedEntries++;
    }
    if (entry.localizations) {
      for (const loc of Object.values(entry.localizations)) {
        rebrandNode(loc);
      }
    }
  }

  const formatted = formatXcodeJSON(catalog) + trailingNewline;
  if (formatted !== raw) {
    fs.writeFileSync(fullPath, formatted);
  }
}

console.log(`✓ Rebranded String Catalogs to Termcast (${updatedEntries} source keys covered)`);
