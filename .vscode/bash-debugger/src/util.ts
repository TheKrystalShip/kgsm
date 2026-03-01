import { execFileSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Find an executable on the system PATH.
 * Returns the absolute path or null if not found.
 */
export function findExecutable(name: string): string | null {
  try {
    const result = execFileSync('which', [name], {
      encoding: 'utf-8',
      timeout: 5000,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    const resolved = result.trim();
    return resolved || null;
  } catch {
    return null;
  }
}

/**
 * Validate that a file exists and is readable.
 */
export function fileExists(filePath: string): boolean {
  try {
    fs.accessSync(filePath, fs.constants.R_OK);
    return true;
  } catch {
    return false;
  }
}

/**
 * Resolve the bash executable path.
 * Checks user override first, then common locations, then PATH.
 */
export function resolveBashPath(override?: string): string | null {
  if (override && fileExists(override)) {
    return override;
  }

  const candidates = ['/usr/bin/bash', '/bin/bash', '/usr/local/bin/bash'];
  for (const candidate of candidates) {
    if (fileExists(candidate)) {
      return candidate;
    }
  }

  return findExecutable('bash');
}

/**
 * Check if bashdb is available on the system.
 * Returns true if bash --debugger is likely to work (bashdb installed).
 */
export function isBashdbAvailable(): boolean {
  // Check if bashdb script exists in common locations
  const candidates = [
    '/usr/share/bashdb/bashdb-main.inc',
    '/usr/local/share/bashdb/bashdb-main.inc',
    '/usr/lib/bashdb/bashdb-main.inc',
  ];

  for (const candidate of candidates) {
    if (fileExists(candidate)) {
      return true;
    }
  }

  // Alternatively, check if bashdb command exists
  return findExecutable('bashdb') !== null;
}

/**
 * Resolve a script path, making it absolute if needed.
 */
export function resolveScriptPath(scriptPath: string, cwd?: string): string {
  if (path.isAbsolute(scriptPath)) {
    return scriptPath;
  }
  return path.resolve(cwd || process.cwd(), scriptPath);
}

/**
 * Get the bash version string.
 * Returns something like "5.1.16(1)-release" or null if bash can't be run.
 */
export function getBashVersion(bashPath: string): string | null {
  try {
    const result = execFileSync(bashPath, ['--version'], {
      encoding: 'utf-8',
      timeout: 5000,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    // First line: "GNU bash, version 5.1.16(1)-release (x86_64-pc-linux-gnu)"
    const match = /version\s+([^\s(]+)/.exec(result);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

/**
 * Parse a bash version string into major.minor.
 * "5.1.16(1)-release" → { major: 5, minor: 1 }
 */
export function parseBashVersion(version: string): { major: number; minor: number } | null {
  const match = /^(\d+)\.(\d+)/.exec(version);
  if (!match) return null;
  return { major: parseInt(match[1], 10), minor: parseInt(match[2], 10) };
}

/**
 * Check if the bash version meets the minimum requirement (4.0+).
 * Returns the version string if OK, or an error message if not.
 */
export function checkBashVersion(bashPath: string): { ok: boolean; version: string; message: string } {
  const version = getBashVersion(bashPath);
  if (!version) {
    return { ok: false, version: 'unknown', message: 'Could not determine bash version.' };
  }

  const parsed = parseBashVersion(version);
  if (!parsed) {
    return { ok: false, version, message: `Could not parse bash version: ${version}` };
  }

  if (parsed.major < 4) {
    return {
      ok: false,
      version,
      message: `Bash ${version} is too old. The debugger requires bash 4.0 or later. ` +
        'Please upgrade bash: sudo apt install bash (Debian/Ubuntu), brew install bash (macOS).',
    };
  }

  if (parsed.major === 4 && parsed.minor < 4) {
    return {
      ok: true,
      version,
      message: `Warning: Bash ${version} detected. Bash 4.4+ is recommended for best debugging support.`,
    };
  }

  return { ok: true, version, message: `Bash ${version} detected.` };
}

/**
 * Get the bashdb version.
 * Returns the version string or null.
 */
export function getBashdbVersion(): string | null {
  try {
    // Try running bashdb --version
    const bashdbPath = findExecutable('bashdb');
    if (!bashdbPath) return null;

    const result = execFileSync(bashdbPath, ['--version'], {
      encoding: 'utf-8',
      timeout: 5000,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    // Output: "bashdb, release 5.0-1.1.2" or similar
    const match = /release\s+(.+)/.exec(result);
    return match ? match[1].trim() : null;
  } catch {
    return null;
  }
}

/**
 * Get detailed prerequisite status for display.
 */
export function getPrerequisiteStatus(bashOverride?: string): {
  bash: { found: boolean; path: string | null; version: string | null; ok: boolean; message: string };
  bashdb: { found: boolean; version: string | null; message: string };
} {
  const bashPath = resolveBashPath(bashOverride);
  const bashFound = bashPath !== null;

  let bashVersionCheck = { ok: false, version: 'unknown', message: 'Bash not found.' };
  if (bashPath) {
    bashVersionCheck = checkBashVersion(bashPath);
  }

  const bashdbAvailable = isBashdbAvailable();
  const bashdbVersion = getBashdbVersion();

  let bashdbMessage = 'bashdb not found. Install it:\n' +
    '  Debian/Ubuntu: sudo apt install bashdb\n' +
    '  macOS: brew install bashdb\n' +
    '  From source: https://github.com/Trepan-Debuggers/bashdb';
  if (bashdbAvailable) {
    bashdbMessage = bashdbVersion ? `bashdb ${bashdbVersion} detected.` : 'bashdb detected.';
  }

  return {
    bash: {
      found: bashFound,
      path: bashPath,
      version: bashVersionCheck.version,
      ok: bashVersionCheck.ok,
      message: bashFound ? bashVersionCheck.message : 'Bash not found. Install bash.',
    },
    bashdb: {
      found: bashdbAvailable,
      version: bashdbVersion,
      message: bashdbMessage,
    },
  };
}
