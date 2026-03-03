import * as path from 'path';

/**
 * A single local↔remote path mapping entry.
 */
export interface PathMapping {
  localRoot: string;
  remoteRoot: string;
}

// Matches ${env:VAR_NAME} placeholders
const ENV_VAR_RE = /\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}/g;

/**
 * Bidirectional path mapper for source path remapping.
 *
 * Translates between local filesystem paths (where source code lives in VS Code)
 * and remote/runtime paths (where scripts actually execute, e.g. sandboxes,
 * containers, Docker volumes).
 *
 * Supports `${env:VAR_NAME}` placeholders in localRoot/remoteRoot values.
 * These are resolved lazily via `resolveEnvVars()` — typically called after the
 * debuggee starts so that env vars set during script execution are available.
 *
 * Mappings are evaluated in order — first match wins.
 */
export class PathMapper {
  private _mappings: PathMapping[];
  private readonly _rawMappings: PathMapping[];
  private _resolved: boolean;

  constructor(mappings?: PathMapping[]) {
    this._rawMappings = mappings || [];
    this._resolved = false;
    this._mappings = this._normalize(this._rawMappings);
  }

  /**
   * Resolve `${env:VAR}` placeholders in mapping paths using the provided
   * environment lookup function. Call this after the debuggee starts so that
   * env vars set during script initialization are available.
   *
   * @param envGetter - async function that returns the value of an env var
   *                    from the debuggee process (e.g., via bashdb eval)
   */
  async resolveEnvVars(envGetter: (name: string) => Promise<string | undefined>): Promise<void> {
    const resolved: PathMapping[] = [];
    for (const m of this._rawMappings) {
      const localRoot = await this._substituteEnvVars(m.localRoot, envGetter);
      const remoteRoot = await this._substituteEnvVars(m.remoteRoot, envGetter);
      resolved.push({ localRoot, remoteRoot });
    }
    this._mappings = this._normalize(resolved);
    this._resolved = true;
  }

  /** Whether env var placeholders have been resolved. */
  get isResolved(): boolean {
    return this._resolved || !this._hasPlaceholders();
  }

  /**
   * Translate a VS Code local path to a remote/runtime path.
   * Used when sending breakpoints and file references to bashdb.
   */
  toRemote(localPath: string): string {
    for (const m of this._mappings) {
      if (localPath === m.localRoot || localPath.startsWith(m.localRoot + path.sep)) {
        return m.remoteRoot + localPath.substring(m.localRoot.length);
      }
    }
    return localPath;
  }

  /**
   * Translate a remote/runtime path back to a VS Code local path.
   * Used when reporting stack traces and positions from bashdb.
   */
  toLocal(remotePath: string): string {
    for (const m of this._mappings) {
      if (remotePath === m.remoteRoot || remotePath.startsWith(m.remoteRoot + path.sep)) {
        return m.localRoot + remotePath.substring(m.remoteRoot.length);
      }
    }
    return remotePath;
  }

  /** Whether any mappings are configured. */
  get hasMappings(): boolean {
    return this._mappings.length > 0;
  }

  private _normalize(mappings: PathMapping[]): PathMapping[] {
    const sepRegex = new RegExp(`[/\\\\]+$`);
    return mappings.map(m => ({
      localRoot: this._normalizePath(m.localRoot, sepRegex),
      remoteRoot: this._normalizePath(m.remoteRoot, sepRegex),
    }));
  }

  private _normalizePath(p: string, sepRegex: RegExp): string {
    // Don't resolve paths with unresolved ${env:VAR} placeholders
    if (ENV_VAR_RE.test(p)) {
      // Reset lastIndex since the regex is global
      ENV_VAR_RE.lastIndex = 0;
      return p.replace(sepRegex, '');
    }
    ENV_VAR_RE.lastIndex = 0;
    return path.resolve(p).replace(sepRegex, '');
  }

  private _hasPlaceholders(): boolean {
    return this._rawMappings.some(
      m => ENV_VAR_RE.test(m.localRoot) || ENV_VAR_RE.test(m.remoteRoot)
    );
  }

  private async _substituteEnvVars(
    value: string,
    envGetter: (name: string) => Promise<string | undefined>,
  ): Promise<string> {
    // Find all ${env:VAR} placeholders
    const matches = [...value.matchAll(ENV_VAR_RE)];
    if (matches.length === 0) return value;

    let result = value;
    for (const match of matches) {
      const fullMatch = match[0];
      const varName = match[1];
      const envValue = await envGetter(varName);
      if (envValue !== undefined) {
        result = result.replace(fullMatch, envValue);
      }
    }
    return result;
  }
}
