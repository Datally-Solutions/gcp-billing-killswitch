variable "GCP_PROJECT_ID" {
  description = "GCP Project ID"
  type        = string
}

variable "GCP_REGION" {
  description = "GCP region"
  type        = string
  default     = "europe-west9"
}

variable "billing_account_id" {
  description = "GCP Billing Account ID (found in Billing console)"
  type        = string
}
