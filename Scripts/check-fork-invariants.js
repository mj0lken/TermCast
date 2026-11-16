#!/usr/bin/env node
// Verifies that Termcast-specific invariants, removed upstream features, and test harness file
// references remain intact after edits or upstream merges.
//
// Usage: node Scripts/check-fork-invariants.js   (run by ./Scripts/lint.sh and sync-upstream)
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");

function read(relPath) {
  return fs.readFileSync(path.join(ROOT, relPath), "utf8");
}

function swiftSources(dir, found = []) {
  if (!fs.existsSync(dir)) return found;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) swiftSources(full, found);
    else if (entry.name.endsWith(".swift")) found.push(full);
  }
  return found;
}

const problems = [];

// 1. Removed upstream Support feature files must stay absent.
const removedPaths = [
  "Tinycast/Features/Support",
  "Tests/SupportTests.swift",
  "docs/features/support.md",
];
for (const rel of removedPaths) {
  if (fs.existsSync(path.join(ROOT, rel))) {
    problems.push(`${rel} exists — Support feature was removed in Termcast`);
  }
}

// 2. No Swift source or test harness may reference removed Support symbols or commands.
const forbiddenSymbols = [
  /\bSupportCoordinator\b/,
  /\bSupportReminderStore\b/,
  /\bSupportReminderSchedule\b/,
  /\bSupportWindowView\b/,
  /\bsupportReminders\b/,
  /\bsupportRemindersEnabled\b/,
  /case\s+support\s*=\s*"command:support"/,
];
const allSwift = [
  ...swiftSources(path.join(ROOT, "Tinycast")),
  ...swiftSources(path.join(ROOT, "Tests")),
];
for (const file of allSwift) {
  const text = fs.readFileSync(file, "utf8");
  const rel = path.relative(ROOT, file);
  for (const pattern of forbiddenSymbols) {
    if (pattern.test(text)) {
      problems.push(`${rel} references removed Support symbol matching ${pattern}`);
    }
  }
}

// 3. Every .swift source path referenced in Scripts/run-tests.sh must exist on disk.
const runTests = read("Scripts/run-tests.sh").replace(/\\\n/g, " ");
if (/\brun\b[^\n]*\bSupportTests\b/.test(runTests)) {
  problems.push("Scripts/run-tests.sh still schedules removed SupportTests");
}
for (const match of runTests.matchAll(/\b((?:Tinycast|Tests)\/[A-Za-z0-9_+./-]+\.swift)\b/g)) {
  const rel = match[1];
  if (!fs.existsSync(path.join(ROOT, rel))) {
    problems.push(`Scripts/run-tests.sh references missing file ${rel}`);
  }
}

// 4. Termcast Backup invariants (.termcast primary, .tinycast + .rayconfig supported).
const backupArchive = read("Tinycast/Features/Backup/Model/BackupArchive.swift");
if (!backupArchive.includes('static let fileExtension = "termcast"')) {
  problems.push('BackupArchive.swift: fileExtension must be "termcast"');
}
if (!backupArchive.includes('static let supportedFileExtensions = ["termcast", "tinycast"]')) {
  problems.push('BackupArchive.swift: supportedFileExtensions must include "termcast" and "tinycast"');
}

const infoPlist = read("Tinycast/Info.plist");
if (!infoPlist.includes("<string>com.mj0lken.termcast.backup</string>")) {
  problems.push("Info.plist: missing com.mj0lken.termcast.backup UTI declaration");
}
if (!infoPlist.includes("<string>com.tinycast.backup</string>")) {
  problems.push("Info.plist: missing com.tinycast.backup UTI declaration");
}

// 5. Termcast About & Palette branding invariants.
const anchors = read("Tinycast/Features/Settings/SettingsAnchor.swift");
if (!/aboutTinycast\s*=\s*Self\(\s*tab:\s*\.about,\s*title:\s*"A Tinycast fork"\s*\)/.test(anchors)) {
  problems.push('SettingsAnchor.swift: .aboutTinycast title must be "A Tinycast fork"');
}

const aboutView = read("Tinycast/Windows/About/AboutView.swift");
for (const forbiddenUrl of [
  "discord.gg/tinycast",
  "x.com/tinycastdev",
  "mailto:abue@tinycast.dev",
  "tinycast.dev/support",
]) {
  if (aboutView.includes(forbiddenUrl)) {
    problems.push(`AboutView.swift: contains removed link ${forbiddenUrl}`);
  }
}

const rootPalette = read("Tinycast/Palette/RootPaletteView.swift");
if (rootPalette.includes("tinycast.dev/changelog")) {
  problems.push("RootPaletteView.swift: Changelog link points to tinycast.dev instead of TermCast releases");
}

// 6. Termcast URL schemes, AI preamble, OAuth client name, and Quicklinks export prefix.
const extDeepLink = read("Tinycast/Features/Extensions/Model/ExtensionDeepLink.swift");
if (!extDeepLink.includes('"termcast"') || !extDeepLink.includes('"termcast-dev"')) {
  problems.push('ExtensionDeepLink.swift: claims(_:) must accept "termcast" and "termcast-dev"');
}

const aiPreamble = read("Tinycast/Features/AI/Model/AIPreamble.swift");
if (!aiPreamble.includes("built into Termcast")) {
  problems.push("AIPreamble.swift: must identify the app as Termcast");
}

const mcpOAuthReq = read("Tinycast/Features/MCP/Model/MCPOAuthRequest.swift");
if (!mcpOAuthReq.includes('"client_name": "Termcast"')) {
  problems.push('MCPOAuthRequest.swift: OAuth client_name must be "Termcast"');
}

const quicklinkCoord = read("Tinycast/Features/Quicklinks/UI/QuicklinkCoordinator.swift");
if (quicklinkCoord.includes('named: "Tinycast-Quicklinks"')) {
  problems.push('QuicklinkCoordinator.swift: export filename prefix must be "Termcast-Quicklinks"');
}

if (problems.length > 0) {
  console.error(`\n✗ ${problems.length} Termcast fork invariant problem(s):`);
  for (const p of problems) console.error(`  ${p}`);
  process.exit(1);
}
