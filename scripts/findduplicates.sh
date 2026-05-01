#!/bin/bash

set -euo pipefail
IFS=$'\n\t'
umask 0002

# Global variables
CURRENT_TIMESTAMP=$(date +'%Y%m%d%H%M%S')
CONFIG_DIR="/findup_config"
RESULT_DIR="/findup_result"
RESULT_FILE="${RESULT_DIR}/fdupes_result_${CURRENT_TIMESTAMP}.txt"
RESULT_FILE_RAW="${RESULT_DIR}/fdupes_result_${CURRENT_TIMESTAMP}_raw.txt"
RESULT_FILE_TMP="${RESULT_DIR}/fdupes_result_${CURRENT_TIMESTAMP}_tmp.txt"
RESULT_FILE_FILTERED="${RESULT_DIR}/fdupes_result_${CURRENT_TIMESTAMP}_filtered.txt"
LOG_FILE="${RESULT_DIR}/${CURRENT_TIMESTAMP}.log"
FDUPES_RECORD_SUMMARY_LINE=''
FDUPES_FILE_LIST=()
MAX_RECORDS=500
BATCH_SIZE=100

# Initialize VERBOSE: accept true/1/yes/y/on (case-insensitive); default false
VERBOSE="${VERBOSE:-false}"
VERBOSE="$(printf '%s' "$VERBOSE" | tr '[:upper:]' '[:lower:]')"
case "$VERBOSE" in
  true|1|yes|y|on) VERBOSE=true ;;
  *)              VERBOSE=false ;;
esac

# Log Configuration
USE_COLOR=false
if [ -t 2 ]; then 
  USE_COLOR=true; 
fi

COL_RESET='\033[0m'
COL_DEBUG='\033[1;37m'
COL_INFO='\033[1;34m'
COL_WARN='\033[1;33m'
COL_ERROR='\033[1;31m'

log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  local ts="$(date +'%Y-%m-%d %H:%M:%S')"
  local color=""
  local out_fd=1

  case "$level" in
    DEBUG) color="$COL_DEBUG"; out_fd=1;;
    INFO)  color="$COL_INFO";  out_fd=1;;
    WARN)  color="$COL_WARN";  out_fd=2;;
    ERROR) color="$COL_ERROR"; out_fd=2;;
    FATAL) color="$COL_ERROR"; out_fd=2;;
    *)     color=""; out_fd=1;;
  esac

  if [ "${USE_COLOR}" = true ]; then
    printf '%b [%s] %s\n' "${color}${ts}${COL_RESET}" "$level" "$msg" >&${out_fd}
  else
    printf '%s [%s] %s\n' "$ts" "$level" "$msg" >&${out_fd}
  fi

  if [ -n "${LOG_FILE:-}" ]; then
    if [ ! -e "${LOG_FILE}" ]; then
      : > "${LOG_FILE}"
    fi

    printf '%s [%s] %s\n' "$ts" "$level" "$msg" >> "${LOG_FILE}" 2>/dev/null || true
  fi

  if [ "$level" = "FATAL" ]; then
    exit 1
  fi
}

log_debug() { 
  if [ "${VERBOSE}" = true ]; then
    log "DEBUG" "$@"
  fi
}

log_info()  { 
  log "INFO"  "$@"; 
}

log_warn()  {
  log "WARN"  "$@"; 
}

log_error() {
  log "ERROR" "$@"; 
}

log_fatal() {
  log "FATAL" "$@"; 
}

# Utility functions for business process
get_file_path_with_file_extensions() {
  local RESULT="${CONFIG_DIR}/file_extension_list.txt"
  echo "${RESULT}"
}

get_file_path_with_search_patterns() {
  local RESULT="${CONFIG_DIR}/search_pattern_list.txt"
  echo "${RESULT}"
}

populate_mount_arrays () {
  log_debug "Populate SEARCH_PATHS and INTERNAL_MOUNT_POINT_NAMES..."
  SEARCH_PATHS=()
  INTERNAL_MOUNT_POINT_NAMES=()

  # adjust upper limit to correspond with amount of VOLUMES defined in docker image (max. 99 due to number formatting)
  for i in {1..10}; do
    # add leading '0'
    local NUM=$(printf "%02d" "$i")
    local NAME="findup_data${NUM}"

    INTERNAL_MOUNT_POINT_NAMES+=( "${NAME}" )
    SEARCH_PATHS+=( "/${NAME}" )
  done  
}

filter_search_paths () {
  log_info "Check search paths..."
  VALID_SEARCH_PATHS=()

  for SEARCH_PATH in "${SEARCH_PATHS[@]}"; do
    if [ -d "${SEARCH_PATH}" ]; then
      VALID_SEARCH_PATHS+=("${SEARCH_PATH}")
    else
      log_warn "Search path does not exist, skipping: ${SEARCH_PATH}"
    fi
  done

  if [ ${#VALID_SEARCH_PATHS[@]} -eq 0 ]; then
    log_error "No valid search paths available."
    exit 3
  fi

  log_info "Files are checked from following valid search paths:"
  printf '  %s\n' "${VALID_SEARCH_PATHS[@]}"  
}

load_include_patterns() {
  INCLUDE_PATTERNS=()

  local FILE_WITH_INCLUDE_PATTERN="$(get_file_path_with_file_extensions)"
  if [ -f "${FILE_WITH_INCLUDE_PATTERN}" ] && [ -r "${FILE_WITH_INCLUDE_PATTERN}" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"
      line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -z "$line" ] && continue
      INCLUDE_PATTERNS+=("$line")
    done <"${FILE_WITH_INCLUDE_PATTERN}"
  else
    if [ -f "${FILE_WITH_INCLUDE_PATTERN}" ]; then
      log_warn "File with INCLUDE patterns exists but is not readable: ${FILE_WITH_INCLUDE_PATTERN} — ignoring."
    else
      log_info "File with INCLUDE patterns not found: ${FILE_WITH_INCLUDE_PATTERN} — scanning all files."
    fi
  fi

  if [ ${#INCLUDE_PATTERNS[@]} -gt 0 ]; then
    log_info "${#INCLUDE_PATTERNS[@]} INCLUDE pattern(s) loaded:"
    printf '  %s\n' "${INCLUDE_PATTERNS[@]}"
  fi

  shopt -s nocasematch
  for INCLUDE_PATTERN_ITEM in "${INCLUDE_PATTERNS[@]:-}"; do
    [ -z "${INCLUDE_PATTERN_ITEM}" ] && continue

    PATTERN="$INCLUDE_PATTERN_ITEM"
    if [[ "$PATTERN" != *\** && "$PATTERN" != */* ]]; then
      PATTERN="*${PATTERN}*"
    fi
    for INTERNAL_MOUNT_POINT_NAME in "${INTERNAL_MOUNT_POINT_NAMES[@]}"; do
      if [[ "${INTERNAL_MOUNT_POINT_NAME}" == $PATTERN ]]; then
        log_error "INCLUDE pattern '${PATTERN}' matches mount point name '${INTERNAL_MOUNT_POINT_NAME}'. Specify pattern."
        exit 5
      fi
    done
  done
  shopt -u nocasematch
}

load_exclude_patterns() {
  EXCLUDE_PATTERNS=()

  local FILE_WITH_EXCLUDE_PATTERN="$(get_file_path_with_search_patterns)"
  if [ -f "${FILE_WITH_EXCLUDE_PATTERN}" ] && [ -r "${FILE_WITH_EXCLUDE_PATTERN}" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"
      line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -z "$line" ] && continue
      EXCLUDE_PATTERNS+=("$line")
    done <"${FILE_WITH_EXCLUDE_PATTERN}"
  else
    if [ -f "${FILE_WITH_EXCLUDE_PATTERN}" ]; then
      log_warn "File with EXCLUDE patterns exists but is not readable: ${FILE_WITH_EXCLUDE_PATTERN} — ignoring."
    else
      log_info "File with EXCLUDE patterns not found: ${FILE_WITH_EXCLUDE_PATTERN} — scanning all files."
    fi
  fi

  if [ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]; then
    log_info "${#EXCLUDE_PATTERNS[@]} EXCLUDE pattern(s) loaded:"
    printf '  %s\n' "${EXCLUDE_PATTERNS[@]}"
  fi

  shopt -s nocasematch
  for EXCLUDE_PATTERN_ITEM in "${EXCLUDE_PATTERNS[@]:-}"; do
    [ -z "${EXCLUDE_PATTERN_ITEM}" ] && continue

    PATTERN="$EXCLUDE_PATTERN_ITEM"
    if [[ "$PATTERN" != *\** && "$PATTERN" != */* ]]; then
      PATTERN="*${PATTERN}*"
    fi
    for INTERNAL_MOUNT_POINT_NAME in "${INTERNAL_MOUNT_POINT_NAMES[@]}"; do
      if [[ "${INTERNAL_MOUNT_POINT_NAME}" == $PATTERN ]]; then
        log_error "EXCLUDE pattern '${PATTERN}' matches mount point name '${INTERNAL_MOUNT_POINT_NAME}'. Specify pattern."
        exit 6
      fi
    done
  done
  shopt -u nocasematch
}

get_fdupes_search_paths() {
  # construct argument list for include pattern
  local FIND_INCLUDE_ARGS=()
  if [ ${#INCLUDE_PATTERNS[@]} -gt 0 ]; then
    for PATTERN in "${INCLUDE_PATTERNS[@]}"; do
      FIND_INCLUDE_ARGS+=("-iname" "$PATTERN" "-o")
    done
    unset 'FIND_INCLUDE_ARGS[${#FIND_INCLUDE_ARGS[@]}-1]'
  fi
  if [ ${#FIND_INCLUDE_ARGS[@]} -gt 0 ]; then
    log_debug "${#FIND_INCLUDE_ARGS[@]} FIND argument(s) for INCLUDE pattern(s) generated:\n$(printf '  %s\n' "${FIND_INCLUDE_ARGS[@]}")"
  fi

  # construct argument list for exclude pattern
  local FIND_EXCLUDE_ARGS=()
  if [ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]; then
    for RAW_PATTERN in "${EXCLUDE_PATTERNS[@]}"; do
      PATTERN="${RAW_PATTERN}"
      if [[ "$PATTERN" != *\** && "$PATTERN" != */* ]]; then
        PATTERN="*${PATTERN}*"
      fi
      FIND_EXCLUDE_ARGS+=("!" "-path" "$PATTERN")
    done
  fi
  if [ ${#FIND_EXCLUDE_ARGS[@]} -gt 0 ]; then
    log_debug "${#FIND_EXCLUDE_ARGS[@]} FIND argument(s) for EXCLUDE pattern(s) generated:\n$(printf '  %s\n' "${FIND_EXCLUDE_ARGS[@]}")"
  fi

  # Get directories from find using include/exclude pattern or all valid search paths
  local FILTERED_DIRECTORIES=()
  if [ ${#FIND_INCLUDE_ARGS[@]} -gt 0 ] && [ ${#FIND_EXCLUDE_ARGS[@]} -gt 0 ]; then
    while IFS= read -r -d '' file; do FILTERED_DIRECTORIES+=( "$(dirname "$file")" ); done < <(find "${VALID_SEARCH_PATHS[@]}" \( "${FIND_INCLUDE_ARGS[@]}" \) "${FIND_EXCLUDE_ARGS[@]}" -type f -print0 | sort -zu)
  elif [ ${#FIND_INCLUDE_ARGS[@]} -gt 0 ]; then
    while IFS= read -r -d '' file; do FILTERED_DIRECTORIES+=( "$(dirname "$file")" ); done < <(find "${VALID_SEARCH_PATHS[@]}" \( "${FIND_INCLUDE_ARGS[@]}" \) -type f -print0 | sort -zu)
  elif [ ${#FIND_EXCLUDE_ARGS[@]} -gt 0 ]; then
    while IFS= read -r -d '' file; do FILTERED_DIRECTORIES+=( "$(dirname "$file")" ); done < <(find "${VALID_SEARCH_PATHS[@]}" "${FIND_EXCLUDE_ARGS[@]}" -type f -print0 | sort -zu)
  else
    FILTERED_DIRECTORIES=( "${VALID_SEARCH_PATHS[@]}" )
  fi
  if [ ${#FILTERED_DIRECTORIES[@]} -eq 0 ]; then
    log_info "No folder for fdupes call identified - exiting"
    exit 0
  fi
  if [ ${#FILTERED_DIRECTORIES[@]} -gt 0 ]; then
    log_debug "${#FILTERED_DIRECTORIES[@]} non-unique folders for fdupes call identified:\n$(printf '  %s\n' "${FILTERED_DIRECTORIES[@]}")"
  fi

  local SORTED_DIRECTORY_INDEX=()
  mapfile -t SORTED_DIRECTORY_INDEX < <(printf '%s\n' "${FILTERED_DIRECTORIES[@]}" | sort -u)

  local NORMALIZED_DIRECTORIES=()
  for DIRECTORY in "${SORTED_DIRECTORY_INDEX[@]}"; do
    [ -z "$DIRECTORY" ] && continue
    if [ ! -d "$DIRECTORY" ]; then
      log_warn "Folder not found/deleted during normalization: ${DIRECTORY}"
      continue
    fi
    if command -v realpath >/dev/null 2>&1; then
      NORMALIZED_DIRECTORY="$(realpath "$DIRECTORY")"
    else
      NORMALIZED_DIRECTORY="$(readlink -f "$DIRECTORY" 2>/dev/null || printf '%s' "$DIRECTORY")"
    fi
    NORMALIZED_DIRECTORIES+=("$NORMALIZED_DIRECTORY")
  done

  SORTED_DIRECTORY_INDEX=()
  mapfile -t SORTED_DIRECTORY_INDEX < <(printf '%s\n' "${NORMALIZED_DIRECTORIES[@]}" | sort -u)

  FDUPES_SEARCH_DIRECTORIES=()
  if [ "${#SORTED_DIRECTORY_INDEX[@]}" -gt "${BATCH_SIZE}" ]; then
    log_warn "${#SORTED_DIRECTORY_INDEX[@]} normalized and sorted directories exceed maximal amount of folders (defined by BATCH_SIZE=${BATCH_SIZE}). Only first ${BATCH_SIZE} folders are passed to fdupes tool."
    FDUPES_SEARCH_DIRECTORIES=( "${SORTED_DIRECTORY_INDEX[@]:0:BATCH_SIZE}" )
  else
    FDUPES_SEARCH_DIRECTORIES=( "${SORTED_DIRECTORY_INDEX[@]}" )
  fi

  if [ ${#FDUPES_SEARCH_DIRECTORIES[@]} -eq 0 ]; then
    log_info "No folder for fdupes call identified - exiting"
    exit 0
  else
    log_debug "${#FDUPES_SEARCH_DIRECTORIES[@]} unique folders for fdupes call identified:\n$(printf '  %s\n' "${FDUPES_SEARCH_DIRECTORIES[@]}")"
  fi
}

run_fdupes() {
  log_info "Start searching for duplicates..."
  : > "${RESULT_FILE_RAW}"
  fdupes -r -S -q "${FDUPES_SEARCH_DIRECTORIES[@]}" >"${RESULT_FILE_RAW}" 2>/dev/null || true
  log_info "fdupes run finished – raw result stored in ${RESULT_FILE_RAW}."
}

process_raw_results() {
  log_info "Remove results with less than 2 remaining duplicates..."

  : > "${RESULT_FILE_TMP}"
  RECORDS=0
  SUM_LINE=''
  FILES=()

  if [ ! -f "${RESULT_FILE_RAW}" ]; then
    log_warn "raw result file not found (${RESULT_FILE_RAW}), creating empty result."
    : > "${RESULT_FILE}"
    return 0
  fi

  while IFS= read -r L || [ -n "$L" ]; do
    if [ -z "$L" ]; then
      if [ ${#FILES[@]} -gt 1 ]; then
        printf '%s\n' "${SUM_LINE}" >> "${RESULT_FILE_TMP}"
        printf '%s\n' "${FILES[@]}" >> "${RESULT_FILE_TMP}"
        printf '\n' >> "${RESULT_FILE_TMP}"
        RECORDS=$((RECORDS+1))

        if [ "${RECORDS}" -ge "${MAX_RECORDS}" ]; then
          break
        fi
      fi

      SUM_LINE=''
      FILES=()
    else
      if [[ "$L" == *"bytes each:"* ]]; then
        SUM_LINE="$L"
      else
        FILES+=("$L")
      fi
    fi
  done < "${RESULT_FILE_RAW}"

  if [ ${#FILES[@]} -gt 1 ] && [ "${RECORDS}" -lt "${MAX_RECORDS}" ]; then
    printf '%s\n' "${SUM_LINE}" >> "${RESULT_FILE_TMP}"
    printf '%s\n' "${FILES[@]}" >> "${RESULT_FILE_TMP}"
    printf '\n' >> "${RESULT_FILE_TMP}"
  fi

  mv -f "${RESULT_FILE_TMP}" "${RESULT_FILE}"
  log_info "processed results written to ${RESULT_FILE} (raw kept at ${RESULT_FILE_RAW})."

  if [ "${RECORDS}" -ge "${MAX_RECORDS}" ]; then
    log_warn "Maximum number of records (${MAX_RECORDS}) reached – output truncated."
  fi
}

apply_filters() {
  log_info "Applying include/exclude filters to result groups..."

  : > "${RESULT_FILE_FILTERED}"

  if [ ! -f "${RESULT_FILE}" ]; then
    log_warn "Result file not found (${RESULT_FILE}), creating empty filtered result."
    : > "${RESULT_FILE_FILTERED}"
    return 0
  fi

  SUM_LINE=''
  FILES=()

  write_group() {
    if [ ${#FILES[@]} -gt 1 ]; then
      printf '%s\n' "${SUM_LINE}" >> "${RESULT_FILE_FILTERED}"
      printf '%s\n' "${FILES[@]}" >> "${RESULT_FILE_FILTERED}"
      printf '\n' >> "${RESULT_FILE_FILTERED}"
    fi
    SUM_LINE=''
    FILES=()
  }

  shopt -s nocasematch

  while IFS= read -r L || [ -n "$L" ]; do
    if [ -z "$L" ]; then
      write_group
    else
      if [[ "$L" == *"bytes each:"* ]]; then
        SUM_LINE="$L"
      else
        file="$L"
        keep=false

        if [ ${#INCLUDE_PATTERNS[@]} -eq 0 ]; then
          keep=true
        else
          for raw_pat in "${INCLUDE_PATTERNS[@]}"; do
            pat="$raw_pat"
            if [[ "$pat" != *"*" && "$pat" != */* ]]; then
              pat="*${pat}*"
            fi
            if [[ "$file" == $pat ]]; then
              keep=true
              break
            fi
          done
        fi

        if $keep && [ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]; then
          for raw_pat in "${EXCLUDE_PATTERNS[@]}"; do
            pat="$raw_pat"
            if [[ "$pat" != *"*" && "$pat" != */* ]]; then
              pat="*${pat}*"
            fi
            if [[ "$file" == $pat ]]; then
              keep=false
              break
            fi
          done
        fi

        $keep && FILES+=("$file")
      fi
    fi
  done < "${RESULT_FILE}"

  write_group

  shopt -u nocasematch

  mv -f "${RESULT_FILE_FILTERED}" "${RESULT_FILE}"
  log_info "Filtering completed – filtered result written to ${RESULT_FILE}."
}

apply_path_mappings() {
  local MAP_FILE="${CONFIG_DIR}/path_mapping_list.txt"

  if [ ! -f "${MAP_FILE}" ] || [ ! -r "${MAP_FILE}" ]; then
    log_info "Path‑mapping file not found or not readable (${MAP_FILE}) – skipping mappings."
    return 0
  fi

  local TMP_MAP="$(mktemp)"
  while IFS= read -r line || [ -n "$line" ]; do
    # Strip comments and trim whitespace
    line="${line%%#*}"
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    if [[ "$line" != *=* ]]; then
      log_warn "Invalid mapping line (skipped): ${line}"
      continue
    fi
    local src="${line%%=*}"
    local dst="${line#*=}"
    src="$(echo "$src" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    dst="$(echo "$dst" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$src" ] && { log_warn "Empty source in mapping (skipped): ${line}"; continue; }
    printf '%d\t%s\t%s\n' "${#src}" "$src" "$dst" >> "${TMP_MAP}"
  done < "${MAP_FILE}"

  if [ ! -s "${TMP_MAP}" ]; then
    log_info "No valid path mappings found – leaving RESULT_FILE unchanged."
    rm -f "${TMP_MAP}"
    return 0
  fi

  sort -rn "${TMP_MAP}" > "${TMP_MAP}.sorted"
  rm -f "${TMP_MAP}"
  TMP_MAP="${TMP_MAP}.sorted"

  local TMP_RESULT="$(mktemp)"
  cp "${RESULT_FILE}" "${TMP_RESULT}" || {
    log_error "Failed to copy ${RESULT_FILE} to temporary file."
    rm -f "${TMP_MAP}" "${TMP_RESULT}"
    return 1
  }

  while IFS=$'\t' read -r _len src dst; do
    log_debug "Applying mapping (sed): [${src}] → [${dst}]"

    # Escape characters that are special to sed's replacement part (/, &)
    esc_src=$(printf '%s' "$src" | sed -e 's/[\/&]/\\&/g')
    esc_dst=$(printf '%s' "$dst" | sed -e 's/[\/&]/\\&/g')

    # Use @ as delimiter to avoid clashes with '/' in paths
    if ! sed -i "s@${esc_src}@${esc_dst}@g" "${TMP_RESULT}"; then
      log_warn "sed replacement failed for src='${src}'. Falling back to mawk."
      mawk -v SRC="$src" -v DST="$dst" '
        {
          while ((i = index($0, SRC)) > 0) {
            $0 = substr($0, 1, i-1) DST substr($0, i + length(SRC))
          }
          print
        }
      ' "${TMP_RESULT}" > "${TMP_RESULT}.tmp" && mv "${TMP_RESULT}.tmp" "${TMP_RESULT}"
    fi
  done < "${TMP_MAP}"

  mv -f "${TMP_RESULT}" "${RESULT_FILE}"
  log_info "Path mappings applied – final result written to ${RESULT_FILE}."

  rm -f "${TMP_MAP}" "${TMP_RESULT}.tmp" 2>/dev/null || true
}

# Main Script Execution
if ! command -v fdupes >/dev/null 2>&1; then
  log_fatal "Tool 'fdupes' not found in PATH."
fi

log_info "FDupes Tool Version: $(fdupes -v)"

log_info "Check folders..."
if [[ ! -d "${CONFIG_DIR}" ]]; then
  log_warn "Directory [${CONFIG_DIR}] for additional configuration settings not existing."
fi

if [[ ! -d "${RESULT_DIR}" ]]; then
  log_error "Directory [${RESULT_DIR}] for result storage not existing."
  exit 2
fi

populate_mount_arrays 
filter_search_paths

load_include_patterns
load_exclude_patterns

get_fdupes_search_paths

run_fdupes

process_raw_results

apply_filters

apply_path_mappings

# make final files host-friendly (best effort; ignore errors)
chmod 0664 "${RESULT_FILE}" 2>/dev/null || true
chmod 0664 "${RESULT_FILE_RAW}" 2>/dev/null || true
chmod 0664 "${LOG_FILE}" 2>/dev/null || true

log_info "All steps completed. Result file is available at [${RESULT_FILE}]."
exit 0
