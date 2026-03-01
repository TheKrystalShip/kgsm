import * as vscode from 'vscode';
import { BashDebugSession } from './bashDebugSession';
import { resolveBashPath, isBashdbAvailable, getPrerequisiteStatus, parseBashVersion } from './util';

export function activate(context: vscode.ExtensionContext): void {
  // Register configuration provider
  const provider = new BashDebugConfigurationProvider();
  context.subscriptions.push(
    vscode.debug.registerDebugConfigurationProvider('bashdb', provider)
  );

  // Register inline debug adapter factory
  const factory = new InlineDebugAdapterFactory();
  context.subscriptions.push(
    vscode.debug.registerDebugAdapterDescriptorFactory('bashdb', factory)
  );
}

export function deactivate(): void {
  // Nothing to clean up
}

class BashDebugConfigurationProvider implements vscode.DebugConfigurationProvider {
  resolveDebugConfiguration(
    folder: vscode.WorkspaceFolder | undefined,
    config: vscode.DebugConfiguration,
    _token?: vscode.CancellationToken,
  ): vscode.ProviderResult<vscode.DebugConfiguration> {
    // If launch.json is missing or empty, provide defaults
    if (!config.type && !config.request && !config.name) {
      const editor = vscode.window.activeTextEditor;
      if (editor && editor.document.languageId === 'shellscript') {
        config.type = 'bashdb';
        config.name = 'Debug Bash Script';
        config.request = 'launch';
        config.program = '${file}';
        config.stopOnEntry = true;
      }
    }

    if (!config.program) {
      return vscode.window.showInformationMessage(
        'Cannot find a program to debug. Set the "program" attribute in launch.json.'
      ).then(() => undefined);
    }

    // Resolve paths
    const workspaceRoot = folder?.uri.fsPath;

    // Default cwd to workspace root or script directory
    if (!config.cwd) {
      config.cwd = workspaceRoot || '${fileDirname}';
    }

    // Default stopOnEntry
    if (config.stopOnEntry === undefined) {
      config.stopOnEntry = true;
    }

    // Check prerequisites
    const status = getPrerequisiteStatus(config.pathBash);

    if (!status.bash.found) {
      vscode.window.showErrorMessage(
        'Bash executable not found. Install bash or set "pathBash" in launch.json.'
      );
      return undefined;
    }

    if (!status.bash.ok) {
      vscode.window.showErrorMessage(status.bash.message);
      return undefined;
    }

    // Warn about old bash versions (4.0-4.3)
    if (status.bash.version && status.bash.ok) {
      const parsed = parseBashVersion(status.bash.version);
      if (parsed && parsed.major === 4 && parsed.minor < 4) {
        vscode.window.showWarningMessage(status.bash.message);
      }
    }

    if (!status.bashdb.found) {
      vscode.window.showErrorMessage(
        'bashdb is not installed. The Bash debugger requires bashdb.\n\n' +
        'Install instructions:\n' +
        '• Debian/Ubuntu: sudo apt install bashdb\n' +
        '• macOS: brew install bashdb\n' +
        '• From source: https://github.com/Trepan-Debuggers/bashdb'
      );
      return undefined;
    }

    // Store resolved bash path in config for runtime use
    config.pathBash = status.bash.path;

    return config;
  }
}

class InlineDebugAdapterFactory implements vscode.DebugAdapterDescriptorFactory {
  createDebugAdapterDescriptor(
    _session: vscode.DebugSession,
    _executable: vscode.DebugAdapterExecutable | undefined,
  ): vscode.ProviderResult<vscode.DebugAdapterDescriptor> {
    return new vscode.DebugAdapterInlineImplementation(new BashDebugSession());
  }
}
