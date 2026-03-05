variable "project_id" {
  description = "GCP Project ID to protect"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west9"
}

variable "billing_account_id" {
  description = "GCP Billing Account ID (found in Billing console)"
  type        = string
}
