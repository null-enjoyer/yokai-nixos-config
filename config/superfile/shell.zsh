# Let Superfile change the directory of the shell that launched it.
function spf() {
  local spf_last_dir="${XDG_STATE_HOME:-$HOME/.local/state}/superfile/lastdir"
  local spf_exit_code=0

  rm -f -- "$spf_last_dir" || return
  command spf "$@" || spf_exit_code=$?
  if (( spf_exit_code == 0 )) && [[ -s "$spf_last_dir" ]]; then
    builtin source "$spf_last_dir" || spf_exit_code=$?
  fi
  rm -f -- "$spf_last_dir"
  return "$spf_exit_code"
}
