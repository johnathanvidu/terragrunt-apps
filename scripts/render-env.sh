#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: bash render-env.sh <space> <env-id> <dev-branch> [--output <path>]' \
    '' \
    'Required arguments:' \
    '  <space>       Space identifier in Torque portal' \
    '  <env-id>      Environment ID in Torque portal' \
    '  <dev-branch>  Git branch to create or update' \
    '' \
    'Optional flags:' \
    '  --output <path>  Where to write the rendered env yaml (defaults to <repo_root>/blueprints/env.yaml)' \
    '' \
    'Environment variables:' \
    '  QTORQUE_API_TOKEN  Bearer token used to authenticate against portal.qtorque.io' \
    '' \
    'Dependencies: curl, yq (v4), git, bash. gh (GitHub CLI) is optional for PR creation.' \
    '' \
    'Example:' \
    '  bash render-env.sh demo-space 123456 dev/my-feature --output environments/demo/env.yaml'
}

require_binary() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required dependency: $1" >&2
    exit 1
  fi
}

parse_args() {
  if [[ $# -lt 3 ]]; then
    echo "Error: missing required arguments" >&2
    usage
    exit 1
  fi

  SPACE="$1"
  ENVID="$2"
  DEV_BRANCH="$3"
  shift 3

  OUTPUT_PATH=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output)
        shift
        if [[ $# -eq 0 ]]; then
          echo "--output requires a value" >&2
          exit 1
        fi
        OUTPUT_PATH="$1"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done
}

ensure_env() {
  if [[ -z "${QTORQUE_API_TOKEN:-}" ]]; then
    echo "QTORQUE_API_TOKEN environment variable must be set" >&2
    exit 1
  fi
}

setup_paths() {
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"
  REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
  WORKDIR=$(mktemp -d)
  trap 'rm -rf "$WORKDIR"' EXIT
  ROOT_YAML="$WORKDIR/root.yaml"
  WORK_YAML="$WORKDIR/working.yaml"
  FINAL_YAML="$WORKDIR/final.yaml"
  if [[ -z "$OUTPUT_PATH" ]]; then
    OUTPUT_PATH="$REPO_ROOT/blueprints/env.yaml"
  elif [[ "$OUTPUT_PATH" != /* ]]; then
    OUTPUT_PATH="$REPO_ROOT/$OUTPUT_PATH"
  fi
}

fetch_root_yaml() {
  URL="https://portal.qtorque.io/api/spaces/${SPACE}/environments/${ENVID}/eac"
  echo "Fetching root YAML from $URL"
  curl -sSf -H "Authorization: Bearer $QTORQUE_API_TOKEN" "$URL" -o "$ROOT_YAML"
}

filter_blueprints() {
  yq eval 'del(.environment) | .grains = (.grains // {} | with_entries(select(.value.kind == "blueprint")))' "$ROOT_YAML" > "$WORK_YAML"
}

removed_grains() {
  yq eval '.grains // {} | to_entries | map(select(.value.kind != "blueprint") | .key) | .[]' "$ROOT_YAML" 2>/dev/null || true
}

output_keys() {
  yq eval '.outputs // {} | keys | .[]' "$WORK_YAML" 2>/dev/null || true
}

blueprint_keys() {
  yq eval '.grains // {} | keys | .[]' "$WORK_YAML" 2>/dev/null || true
}

remove_deleted_outputs() {
  local REMOVED_GRAINS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    REMOVED_GRAINS+=("$line")
  done < <(removed_grains)

  if [[ ${#REMOVED_GRAINS[@]} -eq 0 ]]; then
    return
  fi

  local OUTPUT_KEYS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    OUTPUT_KEYS+=("$line")
  done < <(output_keys)

  for KEY in "${OUTPUT_KEYS[@]}"; do
    [[ -z "$KEY" ]] && continue
    VALUE=$(yq eval ".outputs.\"$KEY\".value" "$WORK_YAML" 2>/dev/null || true)
    for GRAIN in "${REMOVED_GRAINS[@]}"; do
      [[ -z "$GRAIN" ]] && continue
      if [[ "$VALUE" == *"$GRAIN"* ]]; then
        yq eval "del(.outputs.\"$KEY\")" -i "$WORK_YAML"
        break
      fi
    done
  done
  if [[ $(yq eval '.outputs == {}' "$WORK_YAML") == "true" ]]; then
    yq eval 'del(.outputs)' -i "$WORK_YAML"
  fi
}

sanitize_dependencies() {
  local BLUEPRINTS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    BLUEPRINTS+=("$line")
  done < <(blueprint_keys)

  for GRAIN in "${BLUEPRINTS[@]}"; do
    [[ -z "$GRAIN" ]] && continue
    DEP=$(yq eval ".grains.\"$GRAIN\".depends-on" "$WORK_YAML" 2>/dev/null || true)
    if [[ -z "$DEP" || "$DEP" == "null" ]]; then
      continue
    fi
    IFS=',' read -ra DEPS <<< "$DEP"
    NEW_DEPS=()
    for D in "${DEPS[@]}"; do
      CLEAN=$(echo "$D" | xargs)
      for GG in "${BLUEPRINTS[@]}"; do
        if [[ "$CLEAN" == "$GG" ]]; then
          NEW_DEPS+=("$CLEAN")
        fi
      done
    done
    if [[ ${#NEW_DEPS[@]} -eq 0 ]]; then
      yq eval "del(.grains.\"$GRAIN\".depends-on)" -i "$WORK_YAML"
    else
      JOINED=$(IFS=','; echo "${NEW_DEPS[*]}")
      yq eval ".grains.\"$GRAIN\".depends-on = \"$JOINED\"" -i "$WORK_YAML"
    fi
  done
}

inject_tag_inputs() {
  local BLUEPRINTS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    BLUEPRINTS+=("$line")
  done < <(blueprint_keys)

  for GRAIN in "${BLUEPRINTS[@]}"; do
    [[ -z "$GRAIN" ]] && continue
    INPUTS_STATE=$(yq eval ".grains.\"$GRAIN\".spec.inputs" "$WORK_YAML" 2>/dev/null || true)
    if [[ "$INPUTS_STATE" == "null" || "$INPUTS_STATE" == "" || "$INPUTS_STATE" == "[]" ]]; then
      yq eval ".grains.\"$GRAIN\".spec.inputs = [{\"tag\": \"\"}]" -i "$WORK_YAML"
    else
      yq eval ".grains.\"$GRAIN\".spec.inputs += [{\"tag\": \"\"}]" -i "$WORK_YAML"
    fi
  done
}

write_final_yaml() {
  cp "$WORK_YAML" "$FINAL_YAML"
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  cp "$FINAL_YAML" "$OUTPUT_PATH"
  echo "Rendered env yaml written to $OUTPUT_PATH"
}

commit_and_push() {
  cd "$REPO_ROOT"
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  echo "Current branch is $CURRENT_BRANCH"
  if git show-ref --verify --quiet "refs/heads/$DEV_BRANCH"; then
    git checkout "$DEV_BRANCH"
  else
    if git ls-remote --exit-code origin "$DEV_BRANCH" >/dev/null 2>&1; then
      echo "checkouted"
      git checkout -b "$DEV_BRANCH" "origin/$DEV_BRANCH"
    else
      echo "checkouted2"
      git checkout -b "$DEV_BRANCH"
    fi
  fi
  echo outputpath $OUTPUT_PATH
  case "$OUTPUT_PATH" in
    "$REPO_ROOT"/*) RELATIVE_OUTPUT="${OUTPUT_PATH#$REPO_ROOT/}" ;;
    *) RELATIVE_OUTPUT="$OUTPUT_PATH" ;;
  esac
  git add "$RELATIVE_OUTPUT"
  if git diff --cached --quiet; then
    echo "No changes detected in $RELATIVE_OUTPUT; skipping commit and push."
  else
    COMMIT_MSG="Update blueprint for ${SPACE}/${ENVID}"
    git commit -m "$COMMIT_MSG"
    if git push --set-upstream origin "$DEV_BRANCH"; then
      echo "Pushed changes to $DEV_BRANCH"
    else
      echo "Failed to push changes to origin/$DEV_BRANCH" >&2
    fi
    if command -v gh >/dev/null 2>&1; then
      PR_BODY=$(printf '%s\n' \
        "Automated update for environment ${ENVID} in space ${SPACE}." \
        '' \
        'Includes:' \
        '- Rendered blueprint-only grains' \
        '- Cleaned outputs and dependencies' \
        '- Added empty tags input per blueprint grain'
      )
      PR_TITLE="Update blueprint for ${SPACE}/${ENVID}"
      if ! gh pr create --title "$PR_TITLE" --body "$PR_BODY" --base main --head "$DEV_BRANCH"; then
        echo "PR creation skipped or failed." >&2
      fi
    else
      echo "GitHub CLI not available; skipping PR creation."
    fi
  fi
  if [[ "$CURRENT_BRANCH" != "$DEV_BRANCH" ]]; then
    git checkout "$CURRENT_BRANCH"
  fi
}

main() {
  require_binary curl
  require_binary yq
  require_binary git
  parse_args "$@"
  ensure_env
  setup_paths
  fetch_root_yaml
  filter_blueprints
  remove_deleted_outputs
  sanitize_dependencies
  inject_tag_inputs
  write_final_yaml
  commit_and_push
}

main "$@"

