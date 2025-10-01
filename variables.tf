variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "repositories" {
  description = "List of repositories to monitor for drift"
  type = list(object({
    name   = string
    url    = string
    branch = string
    type   = string # "terraform" or "terragrunt"
  }))
}

variable "google_chat_webhook_url" {
  description = "Google Chat webhook URL for notifications"
  type        = string
  sensitive   = true
}

variable "ssh_private_key" {
  description = "SSH private key for repository access"
  type        = string
  sensitive   = true
}

variable "drift_check_schedule" {
  description = "Cron schedule for drift detection (default: daily at 8 AM)"
  type        = string
  default     = "0 8 * * *"
}
