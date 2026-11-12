// The folder the lock reads its PAM rules from: bin/dots-dev's test-password rules only inside a nested session, which sets DOTS_DEV_DIR beside DOTS_PAM_DIR, so DOTS_PAM_DIR alone reaching the live session changes nothing.
export function pamDir(override, devDir) {
  return override && devDir ? override : '/etc/pam.d';
}
