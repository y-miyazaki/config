#!/usr/bin/env bash
# Composite action.yml readers for bats tests (awk only; no yq dependency).
# Load via: source "${_bats_support}/support/action_yml.bash" (after common.bash).

# action_yml_input_names: Print the top-level input names of $1 in file order.
function action_yml_input_names() {
    awk '
        /^inputs:$/ { in_inputs = 1; next }
        /^[a-z]/ { in_inputs = 0 }
        in_inputs && /^  [a-z_]+:$/ { sub(/^  /, ""); sub(/:$/, ""); print }
    ' "$1"
}

# action_yml_input_field: Print field $3 (for example default) of input $2 in $1.
function action_yml_input_field() {
    awk -v input="  $2:" -v field="    $3: " '
        /^inputs:$/ { in_inputs = 1; next }
        /^[a-z]/ { in_inputs = 0 }
        in_inputs && /^  [a-z_]+:$/ { in_input = ($0 == input); next }
        in_inputs && in_input && index($0, field) == 1 { print substr($0, length(field) + 1) }
    ' "$1"
}

# action_yml_output_lines: Print "name: value" for each top-level output of $1.
function action_yml_output_lines() {
    awk '
        /^outputs:$/ { in_outputs = 1; next }
        /^[a-z]/ { in_outputs = 0 }
        in_outputs && /^  [a-z_]+:$/ { sub(/^  /, ""); sub(/:$/, ""); name = $0; next }
        in_outputs && /^    value: / { sub(/^    value: /, ""); print name ": " $0 }
    ' "$1"
}

# action_yml_step_env: Print "KEY: value" lines of the env block of step $2 in $1.
function action_yml_step_env() {
    awk -v name="    - name: $2" '
        /^    - name: / { in_step = ($0 == name); in_env = 0; next }
        in_step && /^      env:$/ { in_env = 1; next }
        in_step && in_env && /^        [A-Za-z_][A-Za-z0-9_]*:/ { sub(/^        /, ""); print; next }
        in_step && in_env { in_env = 0 }
    ' "$1"
}

export -f action_yml_input_names action_yml_input_field action_yml_output_lines action_yml_step_env
