// Instances TreeDataProvider
// Displays KGSM instances in a tree view grouped by blueprint,
// with status indicators and action buttons.

const vscode = require("vscode");

class InstancesProvider {
  /**
   * @param {import("./kgsmClient").KgsmClient} client
   */
  constructor(client) {
    this.client = client;
    this._onDidChangeTreeData = new vscode.EventEmitter();
    this.onDidChangeTreeData = this._onDidChangeTreeData.event;
    /** @type {Map<string, object>} Cached instance info */
    this._instanceCache = new Map();
  }

  refresh() {
    this._onDidChangeTreeData.fire();
  }

  /**
   * @param {vscode.TreeItem} element
   * @returns {vscode.TreeItem}
   */
  getTreeItem(element) {
    return element;
  }

  /**
   * @param {vscode.TreeItem} [element]
   * @returns {Promise<vscode.TreeItem[]>}
   */
  async getChildren(element) {
    if (!element) {
      // Root level: get all instances and group by blueprint
      return this._getBlueprintGroups();
    }

    if (element instanceof BlueprintGroup) {
      return this._getInstanceItems(element.blueprintName);
    }

    return [];
  }

  /**
   * Get blueprint groups that have at least one instance.
   * @returns {Promise<BlueprintGroup[]>}
   */
  async _getBlueprintGroups() {
    const allInstances = await this.client.getInstances();
    if (!allInstances.length) return [];

    // Get info for each instance to determine its blueprint
    const blueprintMap = new Map();

    await Promise.all(
      allInstances.map(async (name) => {
        const info = await this.client.getInstanceInfo(name);
        if (info) {
          this._instanceCache.set(name, info);
          // Extract blueprint name from the blueprint_file path
          const bpName = this._extractBlueprintName(info);
          if (!blueprintMap.has(bpName)) {
            blueprintMap.set(bpName, []);
          }
          blueprintMap.get(bpName).push(name);
        }
      })
    );

    return Array.from(blueprintMap.keys())
      .sort()
      .map((bp) => new BlueprintGroup(bp, blueprintMap.get(bp).length));
  }

  /**
   * Get instance items for a specific blueprint.
   * @param {string} blueprintName
   * @returns {Promise<InstanceItem[]>}
   */
  async _getInstanceItems(blueprintName) {
    const instances = await this.client.getInstances(blueprintName);
    if (!instances.length) return [];

    const items = await Promise.all(
      instances.map(async (name) => {
        const active = await this.client.isActive(name);
        const info = this._instanceCache.get(name) || await this.client.getInstanceInfo(name);
        if (info) this._instanceCache.set(name, info);
        const version = info?.version_file
          ? await this._readVersion(info)
          : null;
        return new InstanceItem(name, active, version, info);
      })
    );

    return items;
  }

  /**
   * Extract the blueprint name from instance info.
   * The blueprint_file path contains the blueprint name.
   * @param {object} info
   * @returns {string}
   */
  _extractBlueprintName(info) {
    if (info.blueprint_file) {
      // Path like: /path/to/blueprints/native/factorio.bp
      const filename = info.blueprint_file.split("/").pop();
      return filename.replace(/\.(bp|docker-compose\.yml)$/, "");
    }
    // Fallback: use the instance name without numeric suffix
    return info.name?.replace(/-\d+$/, "") || "unknown";
  }

  /**
   * Read the installed version from the version file path in instance info.
   * @param {object} info
   * @returns {Promise<string|null>}
   */
  async _readVersion(info) {
    if (!info.version_file) return null;
    try {
      const fs = require("fs");
      const content = fs.readFileSync(info.version_file, "utf8").trim();
      return content || null;
    } catch {
      return null;
    }
  }
}

class BlueprintGroup extends vscode.TreeItem {
  /**
   * @param {string} blueprintName
   * @param {number} instanceCount
   */
  constructor(blueprintName, instanceCount) {
    super(blueprintName, vscode.TreeItemCollapsibleState.Expanded);
    this.blueprintName = blueprintName;
    this.description = `${instanceCount} instance${instanceCount !== 1 ? "s" : ""}`;
    this.iconPath = new vscode.ThemeIcon("package");
    this.contextValue = "blueprintGroup";
  }
}

class InstanceItem extends vscode.TreeItem {
  /**
   * @param {string} name
   * @param {boolean} active
   * @param {string|null} version
   * @param {object|null} info
   */
  constructor(name, active, version, info) {
    super(name, vscode.TreeItemCollapsibleState.None);
    this.instanceName = name;
    this.instanceInfo = info;
    this.active = active;

    this.description = version || "";
    this.tooltip = `${name}${version ? ` (${version})` : ""} — ${active ? "Running" : "Stopped"}`;

    this.iconPath = new vscode.ThemeIcon(
      "circle-filled",
      active
        ? new vscode.ThemeColor("testing.iconPassed")
        : new vscode.ThemeColor("testing.iconFailed")
    );

    this.contextValue = active ? "instancerunning" : "instancestopped";
  }
}

module.exports = { InstancesProvider, BlueprintGroup, InstanceItem };
