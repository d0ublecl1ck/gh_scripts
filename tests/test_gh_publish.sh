#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/gh-publish"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  [[ -f "${file}" ]] || fail "Expected file to exist: ${file}"
  grep -Fq -- "${expected}" "${file}" || fail "Expected '${file}' to contain: ${expected}"
}

assert_git_has_commit() {
  git rev-parse --verify HEAD >/dev/null 2>&1 || fail "Expected repository to have at least one commit"
}

assert_output_not_contains() {
  local output="$1"
  local unexpected="$2"
  if printf '%s' "${output}" | grep -Fq -- "${unexpected}"; then
    fail "Did not expect output to contain: ${unexpected}"
  fi
}

assert_file_not_contains() {
  local file="$1"
  local unexpected="$2"
  [[ -f "${file}" ]] || fail "Expected file to exist: ${file}"
  if grep -Fq -- "${unexpected}" "${file}"; then
    fail "Did not expect '${file}' to contain: ${unexpected}"
  fi
}

make_gh_stub() {
  local bin_dir="$1"
  local log_file="$2"

  cat > "${bin_dir}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${GH_STUB_LOG_FILE:?}"

cmd="${1:-}"
sub="${2:-}"

case "${cmd} ${sub}" in
  "api user")
    printf '%s\n' "gh $*" >> "${log_file}"
    printf '%s\n' "${GH_STUB_LOGIN:-stub-user}"
    exit 0
    ;;
  "auth status")
    exit "${GH_STUB_AUTH_STATUS_EXIT_CODE:-0}"
    ;;
  "auth login")
    printf '%s\n' "gh $*" >> "${log_file}"
    exit 0
    ;;
  "repo create")
    printf '%s\n' "gh $*" >> "${log_file}"
    if [[ -n "${GH_STUB_REPO_CREATE_FAIL_ONCE_MARKER:-}" ]] && [[ ! -f "${GH_STUB_REPO_CREATE_FAIL_ONCE_MARKER}" ]]; then
      : > "${GH_STUB_REPO_CREATE_FAIL_ONCE_MARKER}"
      printf '%s\n' "${GH_STUB_REPO_CREATE_FAIL_ONCE_MESSAGE:-GraphQL: Name already exists on this account (createRepository)}" >&2
      exit 1
    fi
    remote_name=""
    repo_name=""
    shift 2
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --remote=*)
          remote_name="${1#--remote=}"
          shift
          ;;
        --remote)
          remote_name="${2:-}"
          shift 2
          ;;
        --*)
          shift
          ;;
        *)
          if [[ -z "${repo_name}" ]]; then
            repo_name="$1"
          fi
          shift
          ;;
      esac
    done

    if [[ -n "${remote_name}" ]]; then
      remote_root="${GH_STUB_REMOTE_ROOT:-}"
      if [[ -n "${remote_root}" ]]; then
        bare_name="${repo_name//\//_}.git"
        bare_repo="${remote_root}/${bare_name}"
        git init --bare "${bare_repo}" >/dev/null 2>&1
        git remote add "${remote_name}" "${bare_repo}" >/dev/null 2>&1 || true
      fi
    fi
    exit 0
    ;;
  "repo delete")
    printf '%s\n' "gh $*" >> "${log_file}"
    exit 0
    ;;
  *)
    printf '%s\n' "gh $*" >> "${log_file}"
    exit 0
    ;;
esac
EOF

  chmod +x "${bin_dir}/gh"
}

run_case_empty_dir_creates_readme_and_calls_gh() {
  (
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT

    local bin_dir="${tmp}/bin"
    mkdir -p "${bin_dir}"

    local repo_dir="${tmp}/repo"
    mkdir -p "${repo_dir}"

    local gh_log="${tmp}/gh.log"
    : > "${gh_log}"
    make_gh_stub "${bin_dir}" "${gh_log}"

    cd "${repo_dir}"
    export PATH="${bin_dir}:${PATH}"
    export GH_STUB_LOG_FILE="${gh_log}"
    export GH_STUB_REMOTE_ROOT="${tmp}/remotes"
    mkdir -p "${GH_STUB_REMOTE_ROOT}"
    export GIT_AUTHOR_NAME="Test"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test"
    export GIT_COMMITTER_EMAIL="test@example.com"

    "${SCRIPT}" --name test-repo --private --yes

    assert_file_contains "README.md" "# test-repo"
    assert_git_has_commit

    grep -Fq -- "gh repo create test-repo --private --source=. --remote=origin --push" "${gh_log}" \
      || fail "Expected gh repo create call was not recorded (log: ${gh_log})"
  )
}

run_case_existing_file_does_not_overwrite_and_uses_public() {
  (
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT

    local bin_dir="${tmp}/bin"
    mkdir -p "${bin_dir}"

    local repo_dir="${tmp}/repo"
    mkdir -p "${repo_dir}"

    local gh_log="${tmp}/gh.log"
    : > "${gh_log}"
    make_gh_stub "${bin_dir}" "${gh_log}"

    cd "${repo_dir}"
    printf '%s\n' "hello" > hello.txt

    export PATH="${bin_dir}:${PATH}"
    export GH_STUB_LOG_FILE="${gh_log}"
    export GH_STUB_REMOTE_ROOT="${tmp}/remotes"
    mkdir -p "${GH_STUB_REMOTE_ROOT}"
    export GIT_AUTHOR_NAME="Test"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test"
    export GIT_COMMITTER_EMAIL="test@example.com"

    "${SCRIPT}" --name public-repo --public --yes

    [[ -f "hello.txt" ]] || fail "Expected hello.txt to exist"
    assert_git_has_commit

    grep -Fq -- "gh repo create public-repo --public --source=. --remote=origin --push" "${gh_log}" \
      || fail "Expected gh repo create call was not recorded (log: ${gh_log})"
  )
}

run_case_ob_uses_dir_name_public_and_skips_prompts() {
  (
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT

    local bin_dir="${tmp}/bin"
    mkdir -p "${bin_dir}"

    local repo_dir="${tmp}/project-ob"
    mkdir -p "${repo_dir}"

    local gh_log="${tmp}/gh.log"
    : > "${gh_log}"
    make_gh_stub "${bin_dir}" "${gh_log}"

    cd "${repo_dir}"
    export PATH="${bin_dir}:${PATH}"
    export GH_STUB_LOG_FILE="${gh_log}"
    export GH_STUB_REMOTE_ROOT="${tmp}/remotes"
    mkdir -p "${GH_STUB_REMOTE_ROOT}"
    export GIT_AUTHOR_NAME="Test"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test"
    export GIT_COMMITTER_EMAIL="test@example.com"

    local output
    output="$("${SCRIPT}" --ob 2>&1)"

    assert_file_contains "README.md" "# project-ob"
    assert_git_has_commit

    grep -Fq -- "gh repo create project-ob --public --source=. --remote=origin --push" "${gh_log}" \
      || fail "Expected gh repo create call was not recorded (log: ${gh_log})"

    assert_output_not_contains "${output}" "Repository name"
    assert_output_not_contains "${output}" "Visibility:"
    assert_output_not_contains "${output}" "Choose [1/2]"
    assert_output_not_contains "${output}" "About to create GitHub repo"
    assert_output_not_contains "${output}" "Press Enter to continue"
  )
}

run_case_op_uses_dir_name_private_and_skips_prompts() {
  (
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT

    local bin_dir="${tmp}/bin"
    mkdir -p "${bin_dir}"

    local repo_dir="${tmp}/project-op"
    mkdir -p "${repo_dir}"

    local gh_log="${tmp}/gh.log"
    : > "${gh_log}"
    make_gh_stub "${bin_dir}" "${gh_log}"

    cd "${repo_dir}"
    export PATH="${bin_dir}:${PATH}"
    export GH_STUB_LOG_FILE="${gh_log}"
    export GH_STUB_REMOTE_ROOT="${tmp}/remotes"
    mkdir -p "${GH_STUB_REMOTE_ROOT}"
    export GIT_AUTHOR_NAME="Test"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test"
    export GIT_COMMITTER_EMAIL="test@example.com"

    local output
    output="$("${SCRIPT}" --op 2>&1)"

    assert_file_contains "README.md" "# project-op"
    assert_git_has_commit

    grep -Fq -- "gh repo create project-op --private --source=. --remote=origin --push" "${gh_log}" \
      || fail "Expected gh repo create call was not recorded (log: ${gh_log})"

    assert_output_not_contains "${output}" "Repository name"
    assert_output_not_contains "${output}" "Visibility:"
    assert_output_not_contains "${output}" "Choose [1/2]"
    assert_output_not_contains "${output}" "About to create GitHub repo"
    assert_output_not_contains "${output}" "Press Enter to continue"
  )
}

run_case_existing_git_repo_creates_remote_then_pushes_branch() {
  (
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT

    local bin_dir="${tmp}/bin"
    mkdir -p "${bin_dir}"

    local repo_dir="${tmp}/project-existing"
    mkdir -p "${repo_dir}"

    local gh_log="${tmp}/gh.log"
    : > "${gh_log}"
    make_gh_stub "${bin_dir}" "${gh_log}"

    cd "${repo_dir}"
    git init -b main >/dev/null 2>&1
    printf '%s\n' "hello" > hello.txt
    git add -A
    git -c user.name=Test -c user.email=test@example.com commit -m "init" >/dev/null

    export PATH="${bin_dir}:${PATH}"
    export GH_STUB_LOG_FILE="${gh_log}"
    export GH_STUB_REMOTE_ROOT="${tmp}/remotes"
    mkdir -p "${GH_STUB_REMOTE_ROOT}"
    export GIT_AUTHOR_NAME="Test"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test"
    export GIT_COMMITTER_EMAIL="test@example.com"

    local output
    output="$("${SCRIPT}" --name project-existing --private --yes 2>&1)"

    grep -Fq -- "gh repo create project-existing --private --source=. --remote=origin" "${gh_log}" \
      || fail "Expected gh repo create call with source+remote and no push (log: ${gh_log})"
    assert_file_not_contains "${gh_log}" "--push"
    printf '%s' "${output}" | grep -Fq -- "Pushing ref 'main'" \
      || fail "Expected push message in output"
  )
}

run_case_name_exists_can_bind_existing_repo() {
  (
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT

    local bin_dir="${tmp}/bin"
    mkdir -p "${bin_dir}"

    local repo_dir="${tmp}/project-conflict"
    mkdir -p "${repo_dir}"

    local gh_log="${tmp}/gh.log"
    : > "${gh_log}"
    make_gh_stub "${bin_dir}" "${gh_log}"

    cd "${repo_dir}"
    git init -b main >/dev/null 2>&1
    printf '%s\n' "hello" > hello.txt
    git add -A
    git -c user.name=Test -c user.email=test@example.com commit -m "init" >/dev/null

    export PATH="${bin_dir}:${PATH}"
    export GH_STUB_LOG_FILE="${gh_log}"
    export GH_STUB_REMOTE_ROOT="${tmp}/remotes"
    mkdir -p "${GH_STUB_REMOTE_ROOT}"
    mkdir -p "${GH_STUB_REMOTE_ROOT}/tester"
    git init --bare "${GH_STUB_REMOTE_ROOT}/tester/existing-repo.git" >/dev/null 2>&1
    git config url."file://${GH_STUB_REMOTE_ROOT}/".insteadOf "https://github.com/"
    export GH_STUB_LOGIN="tester"
    export GH_STUB_REPO_CREATE_FAIL_ONCE_MARKER="${tmp}/create-failed-once"
    export GIT_AUTHOR_NAME="Test"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test"
    export GIT_COMMITTER_EMAIL="test@example.com"

    local output
    output="$(printf '2\n' | "${SCRIPT}" --name existing-repo --private --yes 2>&1)"

    grep -Fq -- "Name already exists on this account" <<< "${output}" \
      || fail "Expected conflict message in output"
    grep -Fq -- "Bind existing repo and push" <<< "${output}" \
      || fail "Expected bind option in output"
    grep -Fq -- "gh api user -q .login" "${gh_log}" \
      || fail "Expected gh api user call to resolve owner"

    remote_url="$(git remote get-url origin)"
    [[ "${remote_url}" == "https://github.com/tester/existing-repo.git" || "${remote_url}" == "file://${GH_STUB_REMOTE_ROOT}/tester/existing-repo.git" ]] \
      || fail "Unexpected remote URL: ${remote_url}"
  )
}

main() {
  [[ -x "${SCRIPT}" ]] || fail "Script is not executable: ${SCRIPT}"
  run_case_empty_dir_creates_readme_and_calls_gh
  run_case_existing_file_does_not_overwrite_and_uses_public
  run_case_ob_uses_dir_name_public_and_skips_prompts
  run_case_op_uses_dir_name_private_and_skips_prompts
  run_case_existing_git_repo_creates_remote_then_pushes_branch
  run_case_name_exists_can_bind_existing_repo
  printf 'OK\n'
}

main "$@"
