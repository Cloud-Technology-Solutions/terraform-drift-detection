#!/bin/sh
set -e

# Install dependencies
apk add --no-cache unzip wget jq git openssh

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

# Log drift entry
log_drift() {
  jq -n \
    --arg repo "$1" \
    --arg path "$2" \
    --arg workspace "$3" \
    --arg type "$4" \
    '{repository: $repo, path: $path, workspace: $workspace, type: $type}' \
    >> "$DRIFT_ENTRIES"
  DRIFT_DETECTED=true
}

# Run terraform plan with drift detection
check_terraform_drift() {
  local dir="$1" repo="$2" workspace="$3"
  local rel_path="${dir#/workspace/repos/$repo/}"
  
  cd "$dir"
  terraform init -input=false > /dev/null 2>&1 || return 1
  
  [ "$workspace" != "default" ] && terraform workspace select "$workspace" > /dev/null 2>&1
  
  if ! terraform plan -detailed-exitcode -no-color -lock=false > /dev/null 2>&1; then
    [ $? -eq 2 ] && log_drift "$repo" "${rel_path:-(root)}" "$workspace" "terraform"
  fi
}

# Run terragrunt plan with drift detection
check_terragrunt_drift() {
  local dir="$1" repo="$2"
  local rel_path="${dir#/workspace/repos/$repo/}"
  
  cd "$dir"
  terragrunt run init --non-interactive || return 1

  if ! terragrunt plan -detailed-exitcode -no-color -lock=false; then
    [ $? -eq 2 ] log_drift "$repo" "${rel_path:-(root)}" "default" "terragrunt"
  fi
}

# Process repositories
echo "${_REPOSITORIES}" | jq -c '.[]' | while read -r repo; do
  repo_name=$(echo "$repo" | jq -r '.name')
  repo_type=$(echo "$repo" | jq -r '.type')
  repo_path="/workspace/repos/$repo_name"
  
  echo "Checking $repo_name ($repo_type)..."
  
  [ ! -d "$repo_path" ] && { echo "Path not found: $repo_path"; FAILURE_DETECTED=true; continue; }
  
  if [ "$repo_type" = "terraform" ]; then
    find "$repo_path" -name "main.tf" -exec dirname {} \; | sort -u | while read -r tf_dir; do
      cd "$tf_dir"
      terraform init -input=false > /dev/null 2>&1 || continue
      terraform workspace list 2>/dev/null | sed 's/^[* ]*//' | awk 'NF' | while read -r ws; do
        check_terraform_drift "$tf_dir" "$repo_name" "$ws" || FAILURE_DETECTED=true
      done
    done
  elif [ "$repo_type" = "terragrunt" ]; then
    find "$repo_path" -name "terragrunt.hcl" -exec dirname {} \; | sort -u | while read -r tg_dir; do
      check_terragrunt_drift "$tg_dir" "$repo_name" || FAILURE_DETECTED=true
    done
  fi
done

# Generate report
jq -s '.' "$DRIFT_ENTRIES" > /workspace/drift_report.json

# Summary
echo ""
echo "=== Drift Detection Summary ==="
if [ -s "$DRIFT_ENTRIES" ]; then
  echo "⚠️  DRIFT DETECTED:"
  jq -r '.[] | "  - \(.repository)/\(.path) [\(.workspace)]"' /workspace/drift_report.json
else
  echo "✓ No drift detected"
fi

# Save state for external consumption
echo "$DRIFT_DETECTED" > /workspace/drift_detected.txt
echo "$FAILURE_DETECTED" > /workspace/failure_detected.txt