terraform {
  required_version = ">= 1.0"
  backend "gcs" {
    bucket = "hazi-florin-marian"
    prefix = "env/prod"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Service Account for Cloud Build
resource "google_service_account" "drift_detector" {
  account_id   = "terraform-drift-detector"
  display_name = "Terraform Drift Detector Service Account"
  description  = "Service account used by Cloud Build for drift detection"
}

# Grant necessary permissions to the service account
resource "google_project_iam_member" "drift_detector_viewer" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.drift_detector.email}"
}

resource "google_project_iam_member" "drift_detector_compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.drift_detector.email}"
}

resource "google_project_iam_member" "drift_detector_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.drift_detector.email}"
}

resource "google_project_iam_member" "drift_detector_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.drift_detector.email}"
}

resource "google_project_iam_member" "drift_detector_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.drift_detector.email}"
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudbuild.googleapis.com",
    "cloudscheduler.googleapis.com",
    "secretmanager.googleapis.com",
    "compute.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

# Secret Manager for SSH Key
resource "google_secret_manager_secret" "ssh_private_key" {
  secret_id = "terraform-drift-ssh-key"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "ssh_private_key" {
  secret      = google_secret_manager_secret.ssh_private_key.id
  secret_data = var.ssh_private_key
}

# Secret Manager for Google Chat Webhook
resource "google_secret_manager_secret" "chat_webhook" {
  secret_id = "terraform-drift-chat-webhook"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "chat_webhook" {
  secret      = google_secret_manager_secret.chat_webhook.id
  secret_data = var.google_chat_webhook_url
}

# Cloud Storage bucket for Cloud Build logs
resource "google_storage_bucket" "build_logs" {
  name          = "${var.project_id}-drift-detection-logs"
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 30
    }
  }
}

# Cloud Build Trigger
resource "google_cloudbuild_trigger" "drift_detection" {
  name        = "terraform-drift-detection"
  description = "Scheduled drift detection for Terraform/Terragrunt repositories"

  service_account = google_service_account.drift_detector.id

  source_to_build {
    uri       = "https://github.com/Cloud-Technology-Solutions/terraform-drift-detection"
    ref       = "refs/heads/master"
    repo_type = "GITHUB"
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _REPOSITORIES        = jsonencode(var.repositories)
    _SSH_KEY_SECRET      = google_secret_manager_secret.ssh_private_key.secret_id
    _CHAT_WEBHOOK_SECRET = google_secret_manager_secret.chat_webhook.secret_id
    _PROJECT_ID          = var.project_id
  }

  depends_on = [
    google_project_service.required_apis,
    google_secret_manager_secret_version.ssh_private_key,
    google_secret_manager_secret_version.chat_webhook
  ]
}

# Cloud Scheduler Job
resource "google_cloud_scheduler_job" "drift_detection_schedule" {
  name             = "terraform-drift-detection-schedule"
  description      = "Daily scheduled drift detection"
  schedule         = var.drift_check_schedule
  time_zone        = "UTC"
  attempt_deadline = "1800s"

  http_target {
    http_method = "POST"
    uri         = "https://cloudbuild.googleapis.com/v1/projects/${var.project_id}/triggers/${google_cloudbuild_trigger.drift_detection.trigger_id}:run"

    oauth_token {
      service_account_email = google_service_account.drift_detector.email
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Build service account permission to trigger builds
resource "google_project_iam_member" "drift_detector_builds_editor" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.drift_detector.email}"
}
