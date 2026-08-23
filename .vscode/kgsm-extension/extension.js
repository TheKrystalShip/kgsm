// KGSM Extension - VS Code Extension
// Provides a sidebar panel for managing KGSM game server blueprints and instances.

const vscode = require("vscode");
const { KgsmClient } = require("./kgsmClient");
const { BlueprintsProvider } = require("./blueprintsProvider");
const { InstancesProvider } = require("./instancesProvider");

/** @type {NodeJS.Timeout|undefined} */
let pollTimer;

function activate(context) {
  const config = vscode.workspace.getConfiguration("kgsm");
  const kgsmPath = config.get("scriptPath", "/usr/local/bin/kgsm");

  const client = new KgsmClient(kgsmPath);
  const blueprintsProvider = new BlueprintsProvider(client);
  const instancesProvider = new InstancesProvider(client);

  // Register tree data providers
  context.subscriptions.push(
    vscode.window.registerTreeDataProvider("kgsm-blueprints", blueprintsProvider),
    vscode.window.registerTreeDataProvider("kgsm-instances", instancesProvider)
  );

  // --- Settings command ---

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.openSettings", () => {
      vscode.commands.executeCommand("workbench.action.openSettings", "@ext:TheKrystalShip.kgsm-extension");
    })
  );

  // --- Blueprint commands ---

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.openBlueprint", async (item) => {
      const filePath = await client.getBlueprintFilePath(item.blueprintName);
      if (filePath) {
        const doc = await vscode.workspace.openTextDocument(filePath);
        await vscode.window.showTextDocument(doc);
      } else {
        vscode.window.showErrorMessage(`Blueprint file not found: ${item.blueprintName}`);
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.refreshBlueprints", () => {
      blueprintsProvider.refresh();
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.addBlueprint", async (item) => {
      // item is a BlueprintCategory with .filter ("default" | "custom").
      const name = await vscode.window.showInputBox({
        prompt: "Enter a name for the new blueprint (lowercase, no spaces)",
        placeHolder: "my-game",
        validateInput: (value) => {
          if (!value) return "Name is required";
          if (/[^a-z0-9-]/.test(value)) return "Use only lowercase letters, numbers, and hyphens";
          return null;
        },
      });
      if (!name) return;

      // Runtime is now a field inside the unified blueprint, so ask for it up front.
      const runtime = await vscode.window.showQuickPick(["native", "container"], {
        placeHolder: "Select the runtime for this blueprint",
        title: "Blueprint Runtime",
      });
      if (!runtime) return;

      // Resolve the target directory (one flat dir per source).
      const dirs = await client.getBlueprintDirs();
      if (!dirs) {
        vscode.window.showErrorMessage("Failed to resolve KGSM blueprint directories");
        return;
      }

      const targetDir = item.filter === "custom" ? dirs.custom : dirs.default;
      if (!targetDir) {
        vscode.window.showErrorMessage("Could not determine target directory");
        return;
      }

      const fs = require("fs");
      const fspath = require("path");

      // Ensure directory exists
      fs.mkdirSync(targetDir, { recursive: true });

      // One unified file per game: <name>.bp.yaml. Seed it from the documented
      // unified template, substituting the chosen name and runtime.
      const filePath = fspath.join(targetDir, `${name}.bp.yaml`);
      let templateContent;
      const templatePath = fspath.join(client.cwd, "templates", "blueprint.tp");
      try {
        templateContent = fs.readFileSync(templatePath, "utf8")
          .replace(/^name:.*$/m, `name: ${name}`)
          .replace(/^runtime:.*$/m, `runtime: ${runtime}`);
      } catch {
        templateContent =
          `# KGSM Blueprint: ${name}\n` +
          `schema_version: 1\n` +
          `name: ${name}\n` +
          `runtime: ${runtime}\n` +
          `metadata:\n` +
          `  display_name: null\n` +
          `  description: null\n` +
          `  max_players: null\n` +
          `  min_ram_mb: null\n` +
          `  recommended_ram_mb: null\n` +
          `  base_disk_mb: null\n` +
          (runtime === "native"
            ? `native:\n  ports: ''\n  steam_app_id: 0\n  client_steam_app_id: 0\n  executable_file: \n  level_name: default\n`
            : `container:\n  compose: |\n    services:\n      ${name}:\n        image: \n        container_name: \${instance_name}\n        restart: unless-stopped\n`);
      }

      if (fs.existsSync(filePath)) {
        vscode.window.showWarningMessage(`Blueprint file already exists: ${fspath.basename(filePath)}`);
        const doc = await vscode.workspace.openTextDocument(filePath);
        await vscode.window.showTextDocument(doc);
        return;
      }

      fs.writeFileSync(filePath, templateContent, "utf8");
      blueprintsProvider.refresh();

      const doc = await vscode.workspace.openTextDocument(filePath);
      await vscode.window.showTextDocument(doc);
      vscode.window.showInformationMessage(`Created blueprint: ${fspath.basename(filePath)}`);
    })
  );

  // --- Instance commands ---

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.createInstance", async () => {
      // 1. Pick a blueprint
      const blueprints = await client.getBlueprints();
      if (!blueprints || blueprints.length === 0) {
        vscode.window.showErrorMessage("No blueprints found");
        return;
      }

      const blueprint = await vscode.window.showQuickPick(blueprints, {
        placeHolder: "Select a blueprint to install",
        title: "Create New Instance",
      });
      if (!blueprint) return;

      // 2. Pick the library to place it in. An offline one is shown with its
      // state rather than hidden, and is not selectable: placing into a root
      // that is not mounted would write the instance onto whatever filesystem
      // the mount point sits on.
      const libraries = await client.getLibraries();
      if (libraries.length === 0) {
        vscode.window.showErrorMessage(
          "No libraries registered. Run 'kgsm libraries add <path>' first."
        );
        return;
      }

      const pick = await vscode.window.showQuickPick(
        libraries.map((l) => ({
          label: l.name,
          description: l.state,
          detail: l.path,
          library: l.state === "online" ? l.name : null,
        })),
        { placeHolder: "Select a library to place the instance in", title: "Create New Instance" }
      );
      if (!pick) return;
      if (!pick.library) {
        vscode.window.showErrorMessage(`Library '${pick.label}' is not mounted at ${pick.detail}`);
        return;
      }
      const library = pick.library;

      // 3. Optional custom name
      const name = await vscode.window.showInputBox({
        prompt: "Custom instance name (leave empty for auto-generated)",
        placeHolder: "e.g. my-server-01",
        validateInput: (value) => {
          if (value && /[^a-z0-9-]/.test(value)) {
            return "Use only lowercase letters, numbers, and hyphens";
          }
          return null;
        },
      });
      if (name === undefined) return; // cancelled

      // 4. Run install
      await vscode.window.withProgress(
        { location: vscode.ProgressLocation.Notification, title: `Installing ${blueprint}...`, cancellable: false },
        async () => {
          const result = await client.createInstance(blueprint, library, name || undefined);
          if (result.exitCode !== 0) {
            vscode.window.showErrorMessage(`Failed to create instance: ${result.stderr || result.stdout}`);
          } else {
            vscode.window.showInformationMessage(`Instance created from ${blueprint}`);
          }
          instancesProvider.refresh();
        }
      );
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.refreshInstances", () => {
      instancesProvider.refresh();
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.startInstance", async (item) => {
      await vscode.window.withProgress(
        { location: vscode.ProgressLocation.Notification, title: `Starting ${item.instanceName}...` },
        async () => {
          const result = await client.startInstance(item.instanceName);
          if (result.exitCode !== 0) {
            vscode.window.showErrorMessage(`Failed to start ${item.instanceName}: ${result.stderr}`);
          } else {
            vscode.window.showInformationMessage(`Started ${item.instanceName}`);
          }
          instancesProvider.refresh();
        }
      );
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.stopInstance", async (item) => {
      await vscode.window.withProgress(
        { location: vscode.ProgressLocation.Notification, title: `Stopping ${item.instanceName}...` },
        async () => {
          const result = await client.stopInstance(item.instanceName);
          if (result.exitCode !== 0) {
            vscode.window.showErrorMessage(`Failed to stop ${item.instanceName}: ${result.stderr}`);
          } else {
            vscode.window.showInformationMessage(`Stopped ${item.instanceName}`);
          }
          instancesProvider.refresh();
        }
      );
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.restartInstance", async (item) => {
      await vscode.window.withProgress(
        { location: vscode.ProgressLocation.Notification, title: `Restarting ${item.instanceName}...` },
        async () => {
          const result = await client.restartInstance(item.instanceName);
          if (result.exitCode !== 0) {
            vscode.window.showErrorMessage(`Failed to restart ${item.instanceName}: ${result.stderr}`);
          } else {
            vscode.window.showInformationMessage(`Restarted ${item.instanceName}`);
          }
          instancesProvider.refresh();
        }
      );
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.updateInstance", async (item) => {
      const info = item.instanceInfo;
      if (!info || !info.management_file) {
        vscode.window.showErrorMessage(`Cannot update ${item.instanceName}: management file not found`);
        return;
      }

      await vscode.window.withProgress(
        { location: vscode.ProgressLocation.Notification, title: `Updating ${item.instanceName}...` },
        async () => {
          const { execFile } = require("child_process");
          await new Promise((resolve) => {
            execFile(info.management_file, ["--update"], (error, stdout, stderr) => {
              if (error) {
                vscode.window.showErrorMessage(`Failed to update ${item.instanceName}: ${stderr}`);
              } else {
                vscode.window.showInformationMessage(`Updated ${item.instanceName}`);
              }
              resolve();
            });
          });
          instancesProvider.refresh();
        }
      );
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.openInstanceLog", (item) => {
      const terminal = vscode.window.createTerminal(`KGSM Logs: ${item.instanceName}`);
      terminal.sendText(`${kgsmPath} logs ${item.instanceName} --follow`);
      terminal.show();
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.openInstanceConfig", async (item) => {
      const configPath = await client.getInstanceConfigPath(item.instanceName);
      if (configPath) {
        const doc = await vscode.workspace.openTextDocument(configPath);
        await vscode.window.showTextDocument(doc);
      } else {
        vscode.window.showErrorMessage(`Config file not found for ${item.instanceName}`);
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.openManagementScript", async (item) => {
      const info = item.instanceInfo || await client.getInstanceInfo(item.instanceName);
      if (info && info.management_file) {
        const doc = await vscode.workspace.openTextDocument(info.management_file);
        await vscode.window.showTextDocument(doc);
      } else {
        vscode.window.showErrorMessage(`Management script not found for ${item.instanceName}`);
      }
    })
  );

  // --- Auto-refresh ---

  const pollInterval = vscode.workspace.getConfiguration("kgsm").get("pollInterval", 30);
  pollTimer = setInterval(() => {
    instancesProvider.refresh();
  }, pollInterval * 1000);
}

function deactivate() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = undefined;
  }
}

module.exports = { activate, deactivate };

