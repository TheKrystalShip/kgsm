// Blueprints TreeDataProvider
// Displays KGSM blueprints in a tree view with 4 groups:
// Default Native, Default Container, Custom Native, Custom Container.

const vscode = require("vscode");
const path = require("path");

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
        new BlueprintCategory("Default Native", "default", "native"),
        new BlueprintCategory("Default Container", "default", "container"),
        new BlueprintCategory("Custom Native", "custom", "native"),
        new BlueprintCategory("Custom Container", "custom", "container"),
      ];
    }

    if (element instanceof BlueprintCategory) {
      const fetcher =
        element.runtime === "native"
          ? this.client.getNativeBlueprints(element.filter)
          : this.client.getContainerBlueprints(element.filter);

      const names = await fetcher;
      return names.map((name) => new BlueprintItem(name));
    }

    return [];
  }
}

class BlueprintCategory extends vscode.TreeItem {
  /**
   * @param {string} label
   * @param {"default"|"custom"} filter
   * @param {"native"|"container"} runtime
   */
  constructor(label, filter, runtime) {
    super(label, vscode.TreeItemCollapsibleState.Collapsed);
    this.filter = filter;
    this.runtime = runtime;
    this.iconPath = new vscode.ThemeIcon(
      runtime === "native" ? "folder" : "symbol-namespace"
    );
    // contextValue encodes both filter and runtime for menu when-clauses
    this.contextValue = `blueprintCategory-${filter}-${runtime}`;
  }
}

class BlueprintItem extends vscode.TreeItem {
  /**
   * @param {string} name
   */
  constructor(name) {
    super(name, vscode.TreeItemCollapsibleState.None);
    this.blueprintName = name;
    this.iconPath = new vscode.ThemeIcon("file-code");
    this.contextValue = "blueprint";
    this.command = {
      command: "kgsm.openBlueprint",
      title: "Open Blueprint",
      arguments: [this],
    };
    this.tooltip = `Blueprint: ${name}`;
  }
}

module.exports = { BlueprintsProvider, BlueprintCategory, BlueprintItem };
