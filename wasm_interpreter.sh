#!/usr/bin/env bash
# Minimal WASM interpreter in Bash for a small subset of WAT files.
# Usage: ./wasm_interpreter.sh demo.wasm fib 5
set -e

FILE="$1"
FUNC="${2:-fib}"
ARG="${3:-0}"

[[ -f "$FILE" ]] || { echo "File not found: $FILE" >&2; exit 1; }

# Parse WAT file into simple instructions array
declare -a instructions
while read -r line; do
  line=${line%%;;*}
  line=$(echo "$line" | sed -e 's/[()]//g' -e 's/^ *//' -e 's/ *$//')
  [[ -z $line ]] && continue
  case "$line" in
    module*|type*|memory*|export*) continue ;;
    func*|param*|result*) continue ;;
    local\ *i32) continue ;;
    i32.const*) instructions+=("push ${line#* }") ;;
    local.set*) instructions+=("set ${line#* }") ;;
    local.get*) instructions+=("get ${line#* }") ;;
    local.tee*) instructions+=("tee ${line#* }") ;;
    i32.add)    instructions+=("add") ;;
    i32.sub)    instructions+=("sub") ;;
    i32.gt_s)   instructions+=("gt_s") ;;
    loop*)      instructions+=("label ${line#* }") ;;
    br*)        instructions+=("br ${line#* }") ;;
    if)         instructions+=("if") ;;
    end)        instructions+=("end") ;;
    return)     instructions+=("return") ;;
  esac
done < "$FILE"

# Map labels to instruction positions
declare -A label_pos
for i in "${!instructions[@]}"; do
  IFS=' ' read -r op arg <<< "${instructions[$i]}"
  if [[ $op == label ]]; then
    label_pos[$arg]=$((i+1))
  fi
done

# Execute
stack=()
declare -A locals
locals[0]="$ARG"
pc=0
while (( pc < ${#instructions[@]} )); do
  IFS=' ' read -r op arg <<< "${instructions[$pc]}"
  case $op in
    push)
      stack+=("$arg")
      ;;
    set)
      val=${stack[-1]}; unset 'stack[-1]'
      locals[${arg#\$}]="$val"
      ;;
    get)
      stack+=("${locals[${arg#\$}]:-0}")
      ;;
    tee)
      val=${stack[-1]}; locals[${arg#\$}]="$val"
      ;;
    add)
      b=${stack[-1]}; unset 'stack[-1]'; a=${stack[-1]}; unset 'stack[-1]'
      stack+=($((a + b)))
      ;;
    sub)
      b=${stack[-1]}; unset 'stack[-1]'; a=${stack[-1]}; unset 'stack[-1]'
      stack+=($((a - b)))
      ;;
    gt_s)
      b=${stack[-1]}; unset 'stack[-1]'; a=${stack[-1]}; unset 'stack[-1]'
      if (( a > b )); then stack+=(1); else stack+=(0); fi
      ;;
    if)
      cond=${stack[-1]}; unset 'stack[-1]'
      if (( cond == 0 )); then
        depth=1
        while (( depth > 0 )); do
          pc=$((pc+1))
          IFS=' ' read -r op2 arg2 <<< "${instructions[$pc]}"
          [[ $op2 == if ]] && depth=$((depth+1))
          [[ $op2 == end ]] && depth=$((depth-1))
        done
      fi
      ;;
    label)
      ;;
    br)
      pc=$(( label_pos[$arg] ))
      continue
      ;;
    return)
      echo "${stack[-1]}"
      exit 0
      ;;
    end)
      ;;
  esac
  pc=$((pc+1))
done
