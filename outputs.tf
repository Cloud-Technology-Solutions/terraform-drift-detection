output "service_account_email" {
  description = "Service account email for drift detection"
  value       = google_service_account.drift_detector.email
}

output "ssh_key_secret_name" {
  description = "Secret Manager secret name for SSH key"
  value       = google_secret_manager_secret.ssh_private_key.secret_id
}

output "build_trigger_id" {
  description = "Cloud Build trigger ID"
  value       = google_cloudbuild_trigger.drift_detection.trigger_id
}

output "scheduler_job_name" {
  description = "Cloud Scheduler job name"
  value       = google_cloud_scheduler_job.drift_detection_schedule.name
}
