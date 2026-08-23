// KGSM CLI Client
// Wraps kgsm.sh commands and parses their output for the VS Code extension.

const { execFile } = require("child_process");
const path = require("path");

class KgsmClient {
  /**
   * @param {string} kgsmPath - Absolute path to kgsm.sh
   */
  constructor(kgsmPath) {
    this.kgsmPath = kgsmPath;
    this.cwd = path.dirname(kgsmPath);
  }

  /**
   * Execute a kgsm.sh command.
   * @param {string[]} args
   * @returns {Promise<{stdout: string, stderr: string, exitCode: number}>}
   */
  exec(args) {
    return new Promise((resolve, reject) => {
      execFile(this.kgsmPath, args, { cwd: this.cwd }, (error, stdout, stderr) => {
        const exitCode = error ? error.code || 1 : 0;
        resolve({ stdout: stdout || "", stderr: stderr || "", exitCode });
      });
    });
  }

  /**
   * List blueprints.
   * @param {"default"|"custom"|undefined} filter
   * @returns {Promise<string[]>}
   */
  async getBlueprints(filter) {
    const args = ["blueprints", "list"];
    if (filter) args.push(filter);
    args.push("--json");

    const { stdout, exitCode } = await this.exec(args);
    if (exitCode !== 0 || !stdout.trim()) return [];

    try {
      return JSON.parse(stdout);
    } catch {
      return [];
    }
  }

  /**
   * List all blueprints with full detail, keyed by name. Used to surface each
   * blueprint's runtime (native|container), which is now a field inside the
   * unified `<name>.bp.yaml` rather than a separate file family.
   * @returns {Promise<Record<string, object>>} name -> info object (has BlueprintType)
   */
  async getBlueprintsDetailed() {
    const { stdout, exitCode } = await this.exec([
      "blueprints", "list", "detailed", "--json",
    ]);
    if (exitCode !== 0 || !stdout.trim()) return {};

    try {
      return JSON.parse(stdout);
    } catch {
      return {};
    }
  }

  /**
   * Get blueprint directory paths by parsing `./kgsm.sh --paths`.
   * The unified format uses one flat directory per source (no native/container
   * subdirs), so there are just two paths: the system (default) dir and the
   * user (custom) dir, the latter shadowing same-named defaults.
   * @returns {Promise<{default: string, custom: string}|null>}
   */
  async getBlueprintDirs() {
    const { stdout, exitCode } = await this.exec(["--paths"]);
    if (exitCode !== 0) return null;

    const parse = (key) => {
      const match = stdout.match(new RegExp(`${key}:\\s*(.+)`));
      return match ? match[1].trim() : null;
    };

    return {
      default: parse("KGSM_SYSTEM_BLUEPRINTS_DIR"),
      custom: parse("KGSM_USER_BLUEPRINTS_DIR"),
    };
  }

  /**
   * Get the absolute file path for a blueprint.
   * @param {string} name
   * @returns {Promise<string|null>}
   */
  async getBlueprintFilePath(name) {
    const { stdout, exitCode } = await this.exec(["blueprints", "find", name]);
    if (exitCode !== 0) return null;
    return stdout.trim();
  }

  /**
   * List instance names, optionally filtered by blueprint.
   * @param {string} [blueprint]
   * @returns {Promise<string[]>}
   */
  async getInstances(blueprint) {
    const args = ["instances", "list"];
    if (blueprint) args.push(blueprint);
    args.push("--json");

    const { stdout, exitCode } = await this.exec(args);
    if (exitCode !== 0 || !stdout.trim()) return [];

    try {
      return JSON.parse(stdout);
    } catch {
      return [];
    }
  }

  /**
   * List the registered libraries — the roots instances are placed in — each
   * with its state (`online`/`offline`), free/total bytes and instance count.
   * An offline library reports null bytes, because nothing measured them.
   * @returns {Promise<object[]>}
   */
  async getLibraries() {
    const { stdout, exitCode } = await this.exec(["libraries", "list", "--json"]);
    if (exitCode !== 0 || !stdout.trim()) return [];

    try {
      return JSON.parse(stdout);
    } catch {
      return [];
    }
  }

  /**
   * Get instance status (JSON, fast mode).
   * @param {string} name
   * @returns {Promise<object|null>}
   */
  async getInstanceStatus(name) {
    const { stdout, exitCode } = await this.exec([
      "instances", "status", name, "--json", "--fast",
    ]);
    if (exitCode !== 0 || !stdout.trim()) return null;

    try {
      return JSON.parse(stdout);
    } catch {
      return null;
    }
  }

  /**
   * Get instance info as parsed JSON.
   * @param {string} name
   * @returns {Promise<object|null>}
   */
  async getInstanceInfo(name) {
    const { stdout, exitCode } = await this.exec([
      "instances", "info", name, "--json",
    ]);
    if (exitCode !== 0 || !stdout.trim()) return null;

    try {
      return JSON.parse(stdout);
    } catch {
      return null;
    }
  }

  /**
   * Get the absolute path to an instance's config file.
   * @param {string} name
   * @returns {Promise<string|null>}
   */
  async getInstanceConfigPath(name) {
    const { stdout, exitCode } = await this.exec(["instances", "find", name]);
    if (exitCode !== 0) return null;
    return stdout.trim();
  }

  /**
   * Check if an instance is currently running.
   * @param {string} name
   * @returns {Promise<boolean>}
   */
  async isActive(name) {
    const { exitCode } = await this.exec(["is-active", name]);
    return exitCode === 0;
  }

  /**
   * Start an instance.
   * @param {string} name
   * @returns {Promise<{stdout: string, stderr: string, exitCode: number}>}
   */
  startInstance(name) {
    return this.exec(["start", name]);
  }

  /**
   * Stop an instance.
   * @param {string} name
   * @returns {Promise<{stdout: string, stderr: string, exitCode: number}>}
   */
  stopInstance(name) {
    return this.exec(["stop", name]);
  }

  /**
   * Create a new instance from a blueprint.
   *
   * The library is the name of a registered placement root, not a path. Omit it
   * to let the engine resolve one: the configured default_library, else the
   * sole registered library.
   * @param {string} blueprint
   * @param {string} [library]
   * @param {string} [name]
   * @returns {Promise<{stdout: string, stderr: string, exitCode: number}>}
   */
  createInstance(blueprint, library, name) {
    const args = ["install", blueprint];
    if (library) args.push("--library", library);
    if (name) args.push("--name", name);
    return this.exec(args);
  }

  /**
   * Restart an instance.
   * @param {string} name
   * @returns {Promise<{stdout: string, stderr: string, exitCode: number}>}
   */
  restartInstance(name) {
    return this.exec(["restart", name]);
  }
}

module.exports = { KgsmClient };
