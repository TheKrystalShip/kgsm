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
   * List native blueprints (.bp files).
   * @param {"default"|"custom"|undefined} filter
   * @returns {Promise<string[]>}
   */
  async getNativeBlueprints(filter) {
    const args = ["blueprints.native.sh", "list"];
    if (filter) args.push(filter);
    args.push("--json");

    // blueprints.native.sh lives in commands/
    const { execFile } = require("child_process");
    const path = require("path");
    const cmdPath = path.join(this.cwd, "commands", "blueprints.native.sh");

    return new Promise((resolve) => {
      execFile(cmdPath, args.slice(1), { cwd: this.cwd }, (error, stdout) => {
        if (error || !stdout?.trim()) return resolve([]);
        try { resolve(JSON.parse(stdout)); } catch { resolve([]); }
      });
    });
  }

  /**
   * List container blueprints (docker-compose.yml files).
   * @param {"default"|"custom"|undefined} filter
   * @returns {Promise<string[]>}
   */
  async getContainerBlueprints(filter) {
    const args = ["list"];
    if (filter) args.push(filter);
    args.push("--json");

    const { execFile } = require("child_process");
    const path = require("path");
    const cmdPath = path.join(this.cwd, "commands", "blueprints.container.sh");

    return new Promise((resolve) => {
      execFile(cmdPath, args, { cwd: this.cwd }, (error, stdout) => {
        if (error || !stdout?.trim()) return resolve([]);
        try { resolve(JSON.parse(stdout)); } catch { resolve([]); }
      });
    });
  }

  /**
   * Get blueprint directory paths by parsing `./kgsm.sh --paths`.
   * @returns {Promise<{defaultNative: string, defaultContainer: string, customNative: string, customContainer: string}|null>}
   */
  async getBlueprintDirs() {
    const { stdout, exitCode } = await this.exec(["--paths"]);
    if (exitCode !== 0) return null;

    const parse = (key) => {
      const match = stdout.match(new RegExp(`${key}:\\s*(.+)`));
      return match ? match[1].trim() : null;
    };

    return {
      defaultNative: parse("KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR"),
      defaultContainer: parse("KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR"),
      customNative: parse("KGSM_USER_BLUEPRINTS_NATIVE_DIR"),
      customContainer: parse("KGSM_USER_BLUEPRINTS_CONTAINER_DIR"),
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
   * @param {string} blueprint
   * @param {string} installDir
   * @param {string} [name]
   * @returns {Promise<{stdout: string, stderr: string, exitCode: number}>}
   */
  createInstance(blueprint, installDir, name) {
    const args = ["install", blueprint, "--install-dir", installDir];
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
