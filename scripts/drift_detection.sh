#!/bin/sh
set -e

# Install dependencies
apk add --no-cache unzip wget jq bash

# Install Terraform
wget -qO /tmp/terraform.zip https://releases.hashicorp.com/terraform/${_TERRAFORM_VERSION}/terraform_${_TERRAFORM_VERSION}_linux_amd64.zip
unzip /tmp/terraform.zip -d /usr/local/bin/

# Install Terragrunt
wget -qO /usr/local/bin/terragrunt \
  https://github.com/gruntwork-io/terragrunt/releases/download/v${_TERRAGRUNT_VERSION}/terragrunt_linux_amd64
chmod +x /usr/local/bin/terragrunt

# Initialize tracking files
echo "false" > /workspace/drift_detected.txt
echo "false" > /workspace/failure_detected.txt
echo "[]" > /workspace/drift_report.json

# Function to mark failure
mark_failure() {
  echo "true" > /workspace/failure_detected.txt
}

# Function to find all directories with main.tf
find_terraform_dirs() {
  local base_dir="$1"
  find "$base_dir" -type f -name "main.tf" -exec dirname {} \; | sort -u
}

# Function to find all directories with terragrunt.hcl
find_terragrunt_dirs() {
  local base_dir="$1"
  find "$base_dir" -type f -name "terragrunt.hcl" -exec dirname {} \; | sort -u
}

# Function to get all workspaces
get_workspaces() {
  local dir="$1"
  cd "$dir"
  if ! terraform init -input=false >> /tmp/tf_init.log 2>&1; then
    echo "  ⚠️  Failed to initialize Terraform in $dir"
    mark_failure
    return 1
  fi
  terraform workspace list 2>/dev/null | sed 's/^[* ]*//' | awk 'NF'
}

# Function to run terraform plan and capture drift
run_terraform_plan() {
  local dir="$1"
  local repo_name="$2"
  local workspace="$3"
  local relative_path="${dir#/workspace/repos/$repo_name}"
  relative_path="${relative_path#/}"
  if [ -z "$relative_path" ]; then
    relative_path="(root)"
  fi

  echo "Running Terraform plan in: $dir (workspace: $workspace)"
  cd "$dir"

  # Select workspace if not default
  if [ "$workspace" != "default" ]; then
    terraform workspace select "$workspace" > /dev/null 2>&1 || {
      echo "  ⚠️  Failed to select workspace: $workspace"
      mark_failure
      return 1
    }
  fi

  # Run plan and capture output
  if terraform plan -detailed-exitcode -no-color -out=/tmp/tfplan > /tmp/tf_plan.log 2>&1; then
    echo "  ✓ No drift detected"
    return 0
  else
    exit_code=$?
    if [ $exit_code -eq 2 ]; then
      echo "  ⚠️  DRIFT DETECTED!"
      echo "true" > /workspace/drift_detected.txt

      # Create simplified drift entry
      jq -n \
        --arg repo "$repo_name" \
        --arg path "$relative_path" \
        --arg workspace "$workspace" \
        --arg type "terraform" \
        '{repository: $repo, path: $path, workspace: $workspace, type: $type}' \
        >> /workspace/drift_entries.ndjson

      return 2
    else
      echo "  ⚠️  Plan failed with exit code: $exit_code"
      echo "##### START PLAN LOG ####"
      cat /tmp/tf_plan.log
      echo "##### END PLAN LOG ####"
      mark_failure
      return 1
    fi
  fi
}

# Function to run terragrunt plan and capture drift
run_terragrunt_plan() {
  local dir="$1"
  local repo_name="$2"
  local relative_path="${dir#/workspace/repos/$repo_name}"
  relative_path="${relative_path#/}"
  if [ -z "$relative_path" ]; then
    relative_path="(root)"
  fi

  echo "Running Terragrunt plan in: $dir"
  cd "$dir"

  # Run terragrunt plan
  if terragrunt plan -detailed-exitcode -no-color -out=/tmp/tgplan > /tmp/tg_plan.log 2>&1; then
    echo "  ✓ No drift detected"
    return 0
  else
    exit_code=$?
    if [ $exit_code -eq 2 ]; then
      echo "  ⚠️  DRIFT DETECTED!"
      echo "true" > /workspace/drift_detected.txt

      jq -n \
        --arg repo "$repo_name" \
        --arg path "$relative_path" \
        --arg workspace "default" \
        --arg type "terragrunt" \
        '{repository: $repo, path: $path, workspace: $workspace, type: $type}' \
        >> /workspace/drift_entries.ndjson

      return 2
    else
      echo "  ⚠️  Plan failed with exit code: $exit_code"
      mark_failure
      return 1
    fi
  fi
}

# Initialize drift entries file
echo "" > /workspace/drift_entries.ndjson

# Process each repository
echo "${_REPOSITORIES}" | jq -c '.[]' | while IFS= read -r repo; do
  repo_name=$(echo "$repo" | jq -r '.name')
  repo_type=$(echo "$repo" | jq -r '.type')
  repo_path="/workspace/repos/$repo_name"

  echo ""
  echo "================================================"
  echo "Processing repository: $repo_name (type: $repo_type)"
  echo "================================================"

  if [ ! -d "$repo_path" ]; then
    echo "⚠️  Repository path not found: $repo_path"
    mark_failure
    continue
  fi

  if [ "$repo_type" = "terraform" ]; then
    tf_dirs=$(find_terraform_dirs "$repo_path")

    if [ -z "$tf_dirs" ]; then
      echo "No main.tf files found in $repo_name"
      continue
    fi

    echo "$tf_dirs" | while IFS= read -r tf_dir; do
      workspaces=$(get_workspaces "$tf_dir")
      echo "$workspaces" | while IFS= read -r workspace; do
        run_terraform_plan "$tf_dir" "$repo_name" "$workspace" || true
      done
    done

  elif [ "$repo_type" = "terragrunt" ]; then
    tg_dirs=$(find_terragrunt_dirs "$repo_path")

    if [ -z "$tg_dirs" ]; then
      echo "No terragrunt.hcl files found in $repo_name"
      continue
    fi

    echo "$tg_dirs" | while IFS= read -r tg_dir; do
      run_terragrunt_plan "$tg_dir" "$repo_name" || true
    done
  else
    echo "⚠️  Unknown repository type: $repo_type"
    mark_failure
  fi
done

# Consolidate drift entries into JSON array
if [ -s /workspace/drift_entries.ndjson ]; then
  jq -s '.' /workspace/drift_entries.ndjson > /workspace/drift_report.json
else
  echo "[]" > /workspace/drift_report.json
fi

echo ""
echo "================================================"
echo "Drift Detection Summary"
echo "================================================"
drift_detected=$(cat /workspace/drift_detected.txt)
if [ "$drift_detected" = "true" ]; then
  echo "⚠️  DRIFT DETECTED in one or more repositories"
  jq -r '.[] | "  - \(.repository)/\(.path) (workspace: \(.workspace), type: \(.type))"' /workspace/drift_report.json
else
  echo "✓ No drift detected across all repositories"
fi

echo ""
failure_detected=$(cat /workspace/failure_detected.txt)
if [ "$failure_detected" = "true" ]; then
  echo "⚠️  FAILURES DETECTED during execution"
  exit 1
else
  echo "✓ All operations completed successfully"
fi