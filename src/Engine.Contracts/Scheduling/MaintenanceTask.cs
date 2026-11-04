namespace TheKrystalShip.KGSM.Engine.Contracts.Scheduling;

/// <summary>
/// One unit of work a maintenance window performs against an instance.
/// </summary>
/// <remarks>
/// The declaration order is the <b>canonical run order</b>, and it is the only order tasks ever run
/// in: a backup taken after an update archives the new build instead of the rollback point, and a
/// restart is what makes an installed update the running one. <see cref="MaintenanceWindowParser"/>
/// sorts a window's tasks into this order whatever order they were written in, so the token order in
/// the grammar carries no meaning.
/// </remarks>
public enum MaintenanceTask
{
    /// <summary>Archive the instance's saved state.</summary>
    Backup = 0,

    /// <summary>Install a newer build of the game server.</summary>
    Update = 1,

    /// <summary>Bounce the instance.</summary>
    Restart = 2,
}

/// <summary>
/// Conversions between <see cref="MaintenanceTask"/> and the grammar's tokens.
/// </summary>
public static class MaintenanceTaskExtensions
{
    /// <summary>The token that names this task in a <c>maintenance_windows</c> expression.</summary>
    /// <param name="task">The task to render.</param>
    /// <returns><c>backup</c>, <c>update</c> or <c>restart</c>.</returns>
    public static string ToToken(this MaintenanceTask task) => task switch
    {
        MaintenanceTask.Backup => "backup",
        MaintenanceTask.Update => "update",
        MaintenanceTask.Restart => "restart",
        _ => task.ToString().ToLowerInvariant(),
    };

    /// <summary>
    /// Reads a grammar token as a task. Matching is case-insensitive; anything that is not one of
    /// the three tokens fails rather than resolving to a default.
    /// </summary>
    /// <param name="token">The token to read.</param>
    /// <param name="task">The task the token names, when this returns <c>true</c>.</param>
    /// <returns><c>true</c> when <paramref name="token"/> names a task.</returns>
    public static bool TryParse(string? token, out MaintenanceTask task)
    {
        task = MaintenanceTask.Backup;
        if (string.IsNullOrWhiteSpace(token)) return false;

        switch (token.Trim().ToLowerInvariant())
        {
            case "backup": task = MaintenanceTask.Backup; return true;
            case "update": task = MaintenanceTask.Update; return true;
            case "restart": task = MaintenanceTask.Restart; return true;
            default: return false;
        }
    }
}
