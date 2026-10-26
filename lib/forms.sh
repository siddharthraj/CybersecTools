#!/usr/bin/env bash
# Gum-driven add / edit / delete / tag flows.

forms_pick_tags() {
  local current=${1:-} existing selected new csv
  existing=$(db_tag_list)
  selected=""

  if [[ -n $existing ]]; then
    local -a args=(--no-limit --height 12
      --header "Tags · space selects · enter confirms · esc cancels"
      --placeholder "Filter existing tags")
    [[ -n $current ]] && args+=(--selected "${current//, /,}")
    selected=$(printf '%s\n' "$existing" | gum_filter "${args[@]}") || return 1
  fi

  new=$(gum input --header "New tags" --placeholder "comma separated, blank to skip") || return 1
  selected=$(printf '%s' "$selected" | paste -sd, -)
  csv=$selected
  if [[ -n $new ]]; then
    if [[ -n $csv ]]; then csv+=",$new"; else csv=$new; fi
  fi
  normalize_tags_json "$csv" | jq -r 'join(", ")'
}

forms_summary() {
  local name=$1 description=$2 tags=$3 url=$4 usage=$5
  {
    printf '# %s\n\n' "$name"
    [[ -n $tags ]] && printf '**Tags:** %s\n\n' "$tags"
    [[ -n $url ]] && printf '**Reference:** %s\n\n' "$url"
    [[ -n $description ]] && printf '%s\n\n' "$description"
    [[ -n $usage ]] && { printf '# Usage\n\n'; printf '%s\n' "$usage" | sed 's/^/    /'; printf '\n'; }
  } | gum format --type markdown --theme "$(gum_markdown_theme)"
}

forms_add() {
  require_gum || return 1
  require_tty || return 1
  db_init || { ui_error "Could not initialize the database."; return 1; }

  local name description tags url usage tags_json id
  name=$(gum input --header "New tool · name" --placeholder "e.g. Nmap" --char-limit 120) || return 1
  name=$(trim_line "$name")
  valid_tool_name "$name" || { ui_warn "The name must be a single non-empty line."; return 1; }

  if db_name_exists "$name"; then
    if gum confirm "“$name” already exists. Edit it instead?"; then
      id=$(db_resolve_id "$name")
      forms_edit "$id"
    fi
    return 0
  fi

  description=$(gum write --height 6 --header "Description" \
    --placeholder "One or two sentences about what it does") || return 1
  description=$(trim_text "$description")

  tags=$(forms_pick_tags "") || return 1
  tags_json=$(normalize_tags_json "$tags")

  url=$(gum input --header "Reference URL" --placeholder "https://…") || return 1
  url=$(trim_line "$url")
  if [[ -n $url && ! $url =~ ^https?:// ]]; then
    ui_warn "The reference does not start with http(s):// — saving it anyway."
  fi

  usage=$(gum write --height 14 --show-line-numbers \
    --header "Usage guide · optional · markdown" \
    --placeholder "Commands, flags, notes…") || return 1
  usage=$(trim_text "$usage")

  forms_summary "$name" "$description" "$tags" "$url" "$usage" >&2
  gum confirm --default "Save this tool?" || return 1

  if ! id=$(db_insert_tool "$name" "$description" "$url" "$usage" "$tags_json"); then
    ui_error "Could not save “$name”. Is the name already taken?"
    return 1
  fi
  ui_success "Added “$name” (#$id)"
}

forms_edit() {
  local id=$1
  require_gum || return 1
  require_tty || return 1
  db_init || { ui_error "Could not initialize the database."; return 1; }
  [[ $id =~ ^[0-9]+$ ]] || { ui_error "Invalid tool id."; return 1; }

  local json name description url usage tags field new new_id changed=0
  json=$(db_get_tool_json "$id") || { ui_error "Tool not found."; return 1; }

  while true; do
    name=$(jq -r '.name' <<<"$json")
    field=$(gum_choose --height 9 --header "Edit “$name”" \
      "Name" "Description" "Tags" "Reference URL" "Usage guide" "Done") || return 1

    case $field in
      Name)
        new=$(gum input --header "Name" --value "$name" --char-limit 120) || continue
        new=$(trim_line "$new")
        valid_tool_name "$new" || { ui_warn "The name must be a single non-empty line."; continue; }
        if [[ $new != "$name" ]]; then
          new_id=$(db_resolve_id "$new" 2>/dev/null || true)
          if [[ -n $new_id && $new_id != "$id" ]]; then
            ui_warn "Another tool already uses “$new”."
            continue
          fi
        fi
        ;;
      Description)
        description=$(jq -r '.description // ""' <<<"$json")
        new=$(gum write --height 6 --header "Description" --value "$description") || continue
        new=$(trim_text "$new")
        ;;
      Tags)
        tags=$(jq -r '.tags // ""' <<<"$json")
        new=$(forms_pick_tags "$tags") || continue
        ;;
      "Reference URL")
        url=$(jq -r '.url // ""' <<<"$json")
        new=$(gum input --header "Reference URL" --value "$url") || continue
        new=$(trim_line "$new")
        ;;
      "Usage guide")
        usage=$(jq -r '.usage_md // ""' <<<"$json")
        new=$(gum write --height 14 --show-line-numbers --header "Usage guide" --value "$usage") || continue
        new=$(trim_text "$new")
        ;;
      Done|*)
        break
        ;;
    esac

    name=$(jq -r '.name' <<<"$json")
    description=$(jq -r '.description // ""' <<<"$json")
    url=$(jq -r '.url // ""' <<<"$json")
    usage=$(jq -r '.usage_md // ""' <<<"$json")
    tags=$(jq -r '.tags // ""' <<<"$json")

    case $field in
      Name) name=$new ;;
      Description) description=$new ;;
      Tags) tags=$new ;;
      "Reference URL") url=$new ;;
      "Usage guide") usage=$new ;;
    esac

    if ! db_update_tool "$id" "$name" "$description" "$url" "$usage" \
      "$(normalize_tags_json "$tags")"; then
      ui_error "Could not save changes."
      return 1
    fi
    changed=1
    json=$(db_get_tool_json "$id")
  done

  ((changed)) && ui_success "Updated “$(jq -r '.name' <<<"$json")”"
  return 0
}

forms_delete() {
  local id=$1 name
  require_gum || return 1
  require_tty || return 1
  db_init || { ui_error "Could not initialize the database."; return 1; }
  name=$(db_tool_name "$id") || { ui_error "Tool not found."; return 1; }

  gum confirm "Delete “$name”? This cannot be undone." || return 1
  if ! db_delete_tool "$id"; then
    ui_error "Could not delete “$name”."
    return 1
  fi
  ui_success "Deleted “$name”"
}

forms_tags_menu() {
  require_gum || return 1
  require_tty || return 1
  db_init || { ui_error "Could not initialize the database."; return 1; }

  local action tag new src dst
  while true; do
    action=$(gum_choose --height 8 --header "Tags" \
      "List tags" "Rename tag" "Merge tags" "Delete tag" "Back") || return 0

    case $action in
      "List tags")
        if [[ $(db_count_tags) == 0 ]]; then
          ui_info "No tags yet."
        else
          {
            ui_tags_header
            db_tag_counts | while IFS=$'\t' read -r tag count; do
              ui_tag_row "$tag" "$count"
            done
          } | gum pager --soft-wrap --show-line-numbers=false
        fi
        ;;
      "Rename tag")
        tag=$(db_tag_list | gum_filter --height 12 --header "Rename which tag?") || continue
        new=$(gum input --header "New name for “$tag”" --value "$tag") || continue
        new=$(normalize_tags_json "$new" | jq -r '.[0] // empty')
        [[ -n $new ]] || { ui_warn "Invalid tag name."; continue; }
        if db_rename_tag "$tag" "$new"; then
          ui_success "Renamed “$tag” → “$new”"
        else
          ui_error "Could not rename — does “$new” already exist? Use Merge instead."
        fi
        ;;
      "Merge tags")
        src=$(db_tag_list | gum_filter --height 12 --header "Merge which tag?") || continue
        dst=$(db_tag_list | gum_filter --height 12 --header "Into which tag?") || continue
        [[ $src != "$dst" ]] || { ui_warn "Pick two different tags."; continue; }
        gum confirm "Merge “$src” into “$dst”?" || continue
        if db_merge_tags "$src" "$dst"; then
          ui_success "Merged “$src” into “$dst”"
        else
          ui_error "Could not merge those tags."
        fi
        ;;
      "Delete tag")
        tag=$(db_tag_list | gum_filter --height 12 --header "Delete which tag?") || continue
        gum confirm "Delete “$tag” from every tool?" || continue
        if db_delete_tag "$tag"; then
          ui_success "Deleted “$tag”"
        else
          ui_error "Could not delete “$tag”."
        fi
        ;;
      Back|*)
        return 0
        ;;
    esac
  done
}
