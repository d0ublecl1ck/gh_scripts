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
  "auth status")
    exit "${GH_STUB_AUTH_STATUS_EXIT_CODE:-0}"
    ;;
  "auth login")
    printf '%s\n' "gh $*" >> "${log_file}"
    exit 0
    ;;
  "repo create")
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

main() {
  [[ -x "${SCRIPT}" ]] || fail "Script is not executable: ${SCRIPT}"
  run_case_empty_dir_creates_readme_and_calls_gh
  run_case_existing_file_does_not_overwrite_and_uses_public
  run_case_ob_uses_dir_name_public_and_skips_prompts
  run_case_op_uses_dir_name_private_and_skips_prompts
  printf 'OK\n'
}

main "$@"
