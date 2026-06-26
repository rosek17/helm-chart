#!/usr/bin/env bash
#
# helm-deps.sh — topological-sort dependency resolver for local Helm charts.
#
# Walks all Chart.yaml files under the repo root, parses file:// dependencies
# to build a directed graph, topologically sorts it, then runs the requested
# helm action (dep-up, lint, package) on each chart in the correct order.
#
# Usage:
#   ./scripts/helm-deps.sh dep-up          # resolve deps bottom-up
#   ./scripts/helm-deps.sh lint            # dep-up + lint each chart
#   ./scripts/helm-deps.sh package [dir]   # dep-up + lint + package (into dir)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACTION="${1:-dep-up}"
DIST_DIR="${2:-${ROOT_DIR}/dist}"

# ---------------------------------------------------------------------------
# 1. Discover all charts (directories containing Chart.yaml)
# ---------------------------------------------------------------------------
declare -A CHART_DIRS  # name -> absolute dir path

while IFS= read -r chart_file; do
    dir="$(dirname "$chart_file")"
    name="$(grep '^name:' "$chart_file" | head -1 | awk '{print $2}')"
    [ -n "$name" ] && CHART_DIRS["$name"]="$dir"
done < <(find "$ROOT_DIR" -name Chart.yaml -not -path '*/charts/*' -not -path '*/.git/*')

# ---------------------------------------------------------------------------
# 2. Build adjacency list from file:// dependencies
# ---------------------------------------------------------------------------
declare -A DEPS       # chart_name -> space-separated dep names
declare -A IN_DEGREE  # chart_name -> number of incoming edges

for name in "${!CHART_DIRS[@]}"; do
    DEPS["$name"]=""
    IN_DEGREE["$name"]=${IN_DEGREE["$name"]:-0}
done

for name in "${!CHART_DIRS[@]}"; do
    chart_file="${CHART_DIRS[$name]}/Chart.yaml"
    # Extract dependency names that use file:// repositories
    while IFS= read -r dep_name; do
        [ -z "$dep_name" ] && continue
        # Only track deps we actually manage (exist in CHART_DIRS)
        if [[ -n "${CHART_DIRS[$dep_name]:-}" ]]; then
            DEPS["$name"]+="$dep_name "
            IN_DEGREE["$name"]=$(( ${IN_DEGREE["$name"]:-0} + 1 ))
        fi
    done < <(awk '
        /^dependencies:/ { in_deps=1; next }
        in_deps && /^[^ ]/ { in_deps=0 }
        in_deps && /- name:/ { name=$3 }
        in_deps && /repository:.*file:\/\// { print name; name="" }
    ' "$chart_file")
done

# ---------------------------------------------------------------------------
# 3. Kahn's algorithm — topological sort (reverse: leaves first)
# ---------------------------------------------------------------------------
queue=()
for name in "${!CHART_DIRS[@]}"; do
    # Charts with in-degree 0 are leaves — nobody depends on them
    [[ ${IN_DEGREE["$name"]:-0} -eq 0 ]] && queue+=("$name")
done

ORDER=()
while [[ ${#queue[@]} -gt 0 ]]; do
    current="${queue[0]}"
    queue=("${queue[@]:1}")
    ORDER+=("$current")

    # For each chart that depends on $current, decrement its in-degree
    for name in "${!CHART_DIRS[@]}"; do
        for dep in ${DEPS["$name"]}; do
            if [[ "$dep" == "$current" ]]; then
                IN_DEGREE["$name"]=$(( ${IN_DEGREE["$name"]} - 1 ))
                [[ ${IN_DEGREE["$name"]} -eq 0 ]] && queue+=("$name")
            fi
        done
    done
done

# Cycle detection
if [[ ${#ORDER[@]} -ne ${#CHART_DIRS[@]} ]]; then
    echo "ERROR: dependency cycle detected among charts" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 4. Execute the requested action in topological order
# ---------------------------------------------------------------------------
echo "Build order: ${ORDER[*]}"
echo ""

for name in "${ORDER[@]}"; do
    dir="${CHART_DIRS[$name]}"

    echo "========================================="
    echo "  [$ACTION]  $name  ($dir)"
    echo "========================================="

    # Always resolve dependencies first
    helm dependency update "$dir"

    if [[ "$ACTION" == "lint" || "$ACTION" == "package" ]]; then
        helm lint "$dir"
    fi

    if [[ "$ACTION" == "package" ]]; then
        mkdir -p "$DIST_DIR"
        helm package "$dir" --destination "$DIST_DIR"
    fi

    echo ""
done

if [[ "$ACTION" == "package" ]]; then
    helm repo index "$DIST_DIR"
    echo "Packages written to $DIST_DIR"
fi
