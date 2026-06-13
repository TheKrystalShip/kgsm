// Blueprints TreeDataProvider
// Displays KGSM blueprints in a tree view with 2 groups: Default and Custom.
// The unified format makes runtime (native|container) a field inside each
// `<name>.bp.yaml`, not a separate file family — so it is shown per-item (icon
// + tooltip) instead of as a top-level category.

const vscode = require("vscode");

class BlueprintsProvider {
  /**
   * @param {import("./kgsmClient").KgsmClient} client
   */
  constructor(client) {
    this.client = client;
    this._onDidChangeTreeData = new vscode.EventEmitter();
    this.onDidChangeTreeData = this._onDidChangeTreeData.event;
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
      return [
        new BlueprintCategory("Default", "default"),
        new BlueprintCategory("Custom", "custom"),
      ];
    }

    if (element instanceof BlueprintCategory) {
      // Names belonging to this source group, plus a detail map (all blueprints)
      // so each item can show its runtime. BlueprintType is Native/Container.
      const [names, detailed] = await Promise.all([
        this.client.getBlueprints(element.filter),
        this.client.getBlueprintsDetailed(),
      ]);
      return names.map((name) => {
        const runtime = (detailed[name]?.BlueprintType || "").toLowerCase();
        return new BlueprintItem(name, runtime);
      });
    }

    return [];
  }
}

class BlueprintCategory extends vscode.TreeItem {
  /**
   * @param {string} label
   * @param {"default"|"custom"} filter
   */
  constructor(label, filter) {
    super(label, vscode.TreeItemCollapsibleState.Collapsed);
    this.filter = filter;
    this.iconPath = new vscode.ThemeIcon(
      filter === "default" ? "library" : "account"
    );
    this.contextValue = `blueprintCategory-${filter}`;
  }
}

class BlueprintItem extends vscode.TreeItem {
  /**
   * @param {string} name
   * @param {string} [runtime] - "native" | "container" | "" (unknown)
   */
  constructor(name, runtime) {
    super(name, vscode.TreeItemCollapsibleState.None);
    this.blueprintName = name;
    this.runtime = runtime || "";
    // Distinct icon per runtime so the (now per-item) native/container axis
    // stays visible at a glance.
    this.iconPath = new vscode.ThemeIcon(
      runtime === "container" ? "symbol-namespace" : "file-code"
    );
    this.contextValue = "blueprint";
    this.command = {
      command: "kgsm.openBlueprint",
      title: "Open Blueprint",
      arguments: [this],
    };
    this.tooltip = runtime
      ? `Blueprint: ${name} (${runtime})`
      : `Blueprint: ${name}`;
  }
}

module.exports = { BlueprintsProvider, BlueprintCategory, BlueprintItem };
