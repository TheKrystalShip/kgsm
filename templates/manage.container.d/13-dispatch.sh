# =============================================================================
# MAIN DISPATCH
# =============================================================================

# Parse command
command="${1:-}"
shift 2>/dev/null || true

case "$command" in
"")
  show_usage
  exit $EC_ERROR
  ;;
-h | --help | help)
  _cmd_help "$@"
  exit $?
  ;;

# Lifecycle commands
start)
  _cmd_start "$@"
  exit $?
  ;;
stop)
  _cmd_stop "$@"
  exit $?
  ;;
restart)
  _cmd_restart "$@"
  exit $?
  ;;
attach)
  _cmd_attach "$@"
  exit $?
  ;;
kill)
  _cmd_kill "$@"
  exit $?
  ;;
is-active)
  _cmd_is_active "$@"
  exit $?
  ;;

# Server commands
save)
  _cmd_save "$@"
  exit $?
  ;;
input)
  _cmd_input "$@"
  exit $?
  ;;
announce)
  _cmd_announce "$@"
  exit $?
  ;;
kick)
  _cmd_kick "$@"
  exit $?
  ;;
ban)
  _cmd_ban "$@"
  exit $?
  ;;
unban)
  _cmd_unban "$@"
  exit $?
  ;;
status)
  _cmd_status "$@"
  exit $?
  ;;
logs)
  _cmd_logs "$@"
  exit $?
  ;;

# Version & deployment
version)
  _cmd_version "$@"
  exit $?
  ;;
download)
  _cmd_download "$@"
  exit $?
  ;;
deploy)
  _cmd_deploy "$@"
  exit $?
  ;;
update)
  _cmd_update "$@"
  exit $?
  ;;

# Backup management
backup)
  _cmd_backup "$@"
  exit $?
  ;;

# Tier-1 ops: dash-free aliases mirroring the top-level `kgsm instances` CLI
backups)
  _cmd_backups "$@"
  exit $?
  ;;
create-backup)
  _cmd_create_backup "$@"
  exit $?
  ;;
restore-backup)
  _cmd_restore_backup "$@"
  exit $?
  ;;
pin-backup)
  _cmd_pin_backup "$@"
  exit $?
  ;;
unpin-backup)
  _cmd_unpin_backup "$@"
  exit $?
  ;;
check-update)
  _cmd_check_update "$@"
  exit $?
  ;;

*)
  __print_error "Unknown command: $command"
  __print_error "Use '$self help' for available commands"
  exit $EC_INVALID_ARG
  ;;
esac
