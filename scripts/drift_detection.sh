#!/bin/sh
set -e

# Install dependencies
apk add --no-cache unzip wget jq git openssh-client
  
# Add known hosts (required to fetch referenced terragrunt modules)
for host in github.com gitlab.com bitbucket.org; do
  ssh-keyscan -H "$host" >> "${SSH_DIR}/known_hosts" 2>/dev/null || true
done

# Install Terraform
wget -qO /tmp/terraform.zip https://releases.hashicorp.com/terraform/${_TERRAFORM_VERSION}/terraform_${_TERRAFORM_VERSION}_linux_amd64.zip
unzip /tmp/terraform.zip -d /usr/local/bin/

# Install Terragrunt
wget -qO /usr/local/bin/terragrunt \
  https://github.com/gruntwork-io/terragrunt/releases/download/v${_TERRAGRUNT_VERSION}/terragrunt_linux_amd64
chmod +x /usr/local/bin/terragrunt

# Initialize state
DRIFT_DETECTED=false
FAILURE_DETECTED=false
DRIFT_ENTRIES="/tmp/drift_entries.ndjson"
> "$DRIFT_ENTRIES"

# Create temp files to track state across subshells
echo "false" > /tmp/drift_detected.state
echo "false" > /tmp/failure_detected.state

# Log drift entry
log_drift() {
  jq -n \
    --arg repo "$1" \
    --arg path "$2" \
    --arg workspace "$3" \
    --arg type "$4" \
    '{repository: $repo, path: $path, workspace: $workspace, type: $type}' \
    >> "$DRIFT_ENTRIES"
  echo -e "\n" >> "$DRIFT_ENTRIES"
  echo "true" > /tmp/drift_detected.state
}

# Run terraform plan with drift detection
check_terraform_drift() {
  local dir="$1" repo="$2" workspace="$3"
  local rel_path="${dir#/workspace/repos/$repo/}"
  
  cd "$dir"
  
  if [ "$workspace" != "default" ]; then
    if ! terraform workspace select "$workspace" > /dev/null 2>&1; then
      echo "Failed to select workspace $workspace in $dir"
      echo "true" > /tmp/failure_detected.state
      return 1
    fi
  fi
  
  if terraform plan -detailed-exitcode -no-color -lock=false > /dev/null 2>&1; then
    return 0
  else
    local exit_code=$?
    if [ $exit_code -eq 2 ]; then
      log_drift "$repo" "${rel_path:-(root)}" "$workspace" "terraform"
      return 0
    else
      echo "Terraform plan failed with exit code $exit_code in $dir"
      echo "true" > /tmp/failure_detected.state
      return 1
    fi
  fi
}

# Run terragrunt plan with drift detection
check_terragrunt_drift() {
  local dir="$1" repo="$2"
  local rel_path="${dir#/workspace/repos/$repo/}"
  
  cd "$dir"

  if ! terragrunt run -- init > /dev/null 2>&1; then
    echo "Failed to initialize Terragrunt in $dir"
    echo "true" > /tmp/failure_detected.state
    return 1
  fi

  if terragrunt plan -detailed-exitcode -no-color -lock=false > /dev/null 2>&1; then
    return 0
  else
    local exit_code=$?
    if [ $exit_code -eq 2 ]; then
      log_drift "$repo" "${rel_path:-(root)}" "default" "terragrunt"
      return 0
    else
      echo "Terragrunt plan failed with exit code $exit_code in $dir"
      echo "true" > /tmp/failure_detected.state
      return 1
    fi
  fi
}

# Process repositories
echo "${_REPOSITORIES}" | jq -c '.[]' | while read -r repo; do
  repo_name=$(echo "$repo" | jq -r '.name')
  repo_type=$(echo "$repo" | jq -r '.type')
  repo_path="/workspace/repos/$repo_name"
  
  echo "Checking $repo_name ($repo_type)..."
  
  [ ! -d "$repo_path" ] && { echo "Path not found: $repo_path"; echo "true" > /tmp/failure_detected.state; continue; }
  
  if [ "$repo_type" = "terraform" ]; then
    find "$repo_path" -name "main.tf" -exec dirname {} \; | sort -u | while read -r tf_dir; do
      cd "$tf_dir"
      if ! terraform init -input=false > /dev/null 2>&1; then
        echo "true" > /tmp/failure_detected.state
        continue
      fi
      terraform workspace list 2>/dev/null | sed 's/^[* ]*//' | awk 'NF' | while read -r ws; do
        check_terraform_drift "$tf_dir" "$repo_name" "$ws" || echo "true" > /tmp/failure_detected.state
      done
    done
  elif [ "$repo_type" = "terragrunt" ]; then
    find "$repo_path" -name "terragrunt.hcl" -exec dirname {} \; | sort -u | while read -r tg_dir; do
      if echo "$tg_dir" | grep -q "\.terragrunt-cache"; then
        continue
      fi
      check_terragrunt_drift "$tg_dir" "$repo_name" || echo "true" > /tmp/failure_detected.state
    done
  fi
done

# Read the final state from temp files
DRIFT_DETECTED=$(cat /tmp/drift_detected.state)
FAILURE_DETECTED=$(cat /tmp/failure_detected.state)

# Generate report
if [ -s "$DRIFT_ENTRIES" ]; then
  jq -s '.' "$DRIFT_ENTRIES" > /workspace/drift_report.json
else
  echo "[]" > /workspace/drift_report.json
fi

# Summary
echo ""
echo "=== Drift Detection Summary ==="
if [ "$DRIFT_DETECTED" = "true" ]; then
  echo "⚠️  DRIFT DETECTED:"
  if [ -s "/workspace/drift_report.json" ]; then
    jq -r '.[] | "  - \(.repository)/\(.path) [\(.workspace)] (\(.type))"' /workspace/drift_report.json
  fi
else
  echo "✓ No drift detected"
fi

# Save state for external consumption
echo "$DRIFT_DETECTED" > /workspace/drift_detected.txt
echo "$FAILURE_DETECTED" > /workspace/failure_detected.txt

# Cleanup temp files
rm -f /tmp/drift_detected.state /tmp/failure_detected.state