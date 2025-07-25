#!/bin/bash

WHITELIST_FILE="/etc/docker/whitelist_images.txt"
LOG_FILE="/var/log/docker-image-cleanup.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
AGE_THRESHOLD_HR=72

log_message() {
    echo "$TIMESTAMP - $1" >> "$LOG_FILE"
}

# Input: repo name 
# Output: 0 if whitelisted, 1 if not
# Ex: nginx, redis, postgres
is_whitelisted() {
  local repo="$1"
  ## -F option treats the pattern as a fixed string
  ## -x option matches the whole line
  ## -q quiet
  grep -Fxq "$repo" "$WHITELIST_FILE"
}

has_child_image() {
    local candidate_parent_id="$1" # ID of the image we want to check for child images
    # Get a list of all existing Image IDs
    local all_image_ids=$(docker images -q 2>/dev/null)
    # Iterate through each Image ID and check its parent
    for img_id in $all_image_ids; do
        # Get the Parent ID of the current image in the loop
        local parent_of_current_img=$(docker inspect --format '{{.Parent}}' "$img_id" 2>/dev/null)
        # Compare this Parent ID with the ID of the image we want to check (candidate_parent_id)
        # If they match, it means there is a child image depending on candidate_parent_id
        if [ "$parent_of_current_img" = "sha256:$candidate_parent_id" ] || [ "$parent_of_current_img" = "$candidate_parent_id" ]; then
            return 0 # Return 0 (true) if a child image is found
        fi
    done

    return 1 # Return 1 (false) if no child images are found
}


# input: repo name
# output: latest tag of the repo
# Ex: nginx
# -> latest ( or the most recently created tag )
get_latest_tag() {
    local repo="$1"
    # Step 1: get all tags of the repo with created date and image ID
    # Format: REPO TAG CREATED_AT_STRING IMAGE_ID
    # Ex: # alpine 3.20 2025-07-15 11:31:35 +0000 UTC 12345
    # Ex: # alpine 3.19 2025-07-15 11:32:09 +0000 UTC 67890
    #
    # Pipe 1: Use awk to parse the CreatedAt string into a Unix timestamp.
    # We construct a new line: UnixTimestamp REPO TAG CreatedAtString
    # Then sort by the UnixTimestamp (column 1) in reverse order.
    # Finally, extract the TAG name (now column 3).
    docker images --format '{{.Repository}} {{.Tag}} {{.CreatedAt}} {{.ID}}' | \
        grep "^$repo " | \
        awk '{
            # Extract the date/time string, which might have spaces
            # Reconstruct the original line but with Unix timestamp first
            # Join the date and time parts, ignore offset and timezone for date -d
            timestamp = mktime(gensub(/([0-9]{4}-[0-9]{2}-[0-9]{2}) ([0-9]{2}:[0-9]{2}:[0-9]{2}).*/, "\\1 \\2", "g", $3 " " $4));
            print timestamp, $1, $2, $3, $4, $5, $6; # unix_ts repo tag year-mo-da hr:mi:se offset timezone
        }' | \
        sort -rnk1 | \
        head -n1 | \
        awk '{print $3}' # The tag is now the 3rd column
}

cleanup_containers() {
    log_message "Starting container cleanup..."
    # Remove stopped containers with status exited
    local stopped_containers=$(docker ps -aq --filter "status=exited")

    if [ -n "$stopped_containers" ]; then
        echo "$stopped_containers" | xargs docker rm
        log_message "Removed stopped containers: $(echo $stopped_containers | wc -w) containers"
    else
        log_message "No stopped containers to remove"
    fi
}

# Remove the none:none images
cleanup_dangling_images() {
  log_message "Checking dangling images..."
  local dangling_images
  dangling_images=$(docker images -q --filter "dangling=true") # id of images
  if [ -n "$dangling_images" ]; then
    echo "$dangling_images" | xargs -r docker rmi -f >> "$LOG_FILE" 2>&1
    log_message "Removed $(echo "$dangling_images" | wc -l) dangling images."
  else
    log_message "No dangling images found."
  fi
}

# Skip images that:
#   - Are used by any container (even stopped ones)
#   - Are in whitelist *and* latest tag
cleanup_unused_images() {
  log_message "Scanning for unused images ..."

  # Loop through all images
  # Format: "REPO:TAG IMAGE_ID"
  # Ex: nginx:latest 123456789abc
  # Ex: redis:6.2 987654321def
  # Ex: postgres:14.1 112233445566
  docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | while read -r line; do
    repo_tag=$(echo "$line" | awk '{print $1}')
    image_id=$(echo "$line" | awk '{print $2}')

    repo=$(echo "$repo_tag" | cut -d: -f1)
    tag=$(echo "$repo_tag" | cut -d: -f2)

    # Skip if repo in whitelist AND is latest tag
    if is_whitelisted "$repo"; then
      latest_tag=$(get_latest_tag "$repo")
      if [ "$tag" = "$latest_tag" ]; then
        log_message "Skipped whitelisted latest tag: $repo_tag"
        continue
      fi
    fi

    # Check if image is used by a container
    if docker ps -aq --filter "ancestor=$image_id" | grep -q .; then
      log_message "Skipped used image: $repo_tag"
      continue
    fi

    # Check image age
    # 2025-07-21T12:34:56.123456789Z
    created_at=$(docker inspect --format '{{.Created}}' "$image_id" 2>/dev/null)
    if [ -z "$created_at" ]; then
      continue
    fi
    created_ts=$(date -d "$created_at" +%s)
    now_ts=$(date +%s)
    age_hr=$(( (now_ts - created_ts) / 3600 ))

    if [ "$age_hr" -ge "$AGE_THRESHOLD_HR" ]; then
      if has_child_image "$image_id"; then
        log_message "Skipped image with dependent child: $repo_tag ($image_id)"
        continue
      fi
      docker rmi -f "$repo_tag" >> "$LOG_FILE" 2>&1
      log_message "Removed unused image: $repo_tag (${age_hr}h old)"
    else
      log_message "Skipped recent image: $repo_tag (${age_hr}h old)"
    fi
  done
}

main() {
  if [ ! -f "$WHITELIST_FILE" ]; then
    log_message "Whitelist file not found: $WHITELIST_FILE"
    exit 1
  fi
  log_message "=== Docker image cleanup started ==="
  cleanup_dangling_images
  cleanup_containers
  cleanup_unused_images
  log_message "=== Docker image cleanup finished ==="
}

main
