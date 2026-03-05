terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "cat-litter-monitor-tfstate"
    prefix = "killswitch"
  }
}

provider "google" {
  project = var.GCP_PROJECT_ID
  region  = var.GCP_PROJECT_ID
}

# -------------------------------------------------------
# APIs
# -------------------------------------------------------
resource "google_project_service" "apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbilling.googleapis.com",
    "billingbudgets.googleapis.com",
    "artifactregistry.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

# -------------------------------------------------------
# Pub/Sub topic
# -------------------------------------------------------
resource "google_pubsub_topic" "billing_alerts" {
  name       = "billing-killswitch-alerts"
  depends_on = [google_project_service.apis]
}

# -------------------------------------------------------
# Service Account for Cloud Function
# -------------------------------------------------------
resource "google_service_account" "killswitch_sa" {
  account_id   = "billing-killswitch-sa"
  display_name = "Billing Kill Switch SA"
}

resource "google_billing_account_iam_member" "killswitch_billing_admin" {
  billing_account_id = var.billing_account_id
  role               = "roles/billing.admin"
  member             = "serviceAccount:${google_service_account.killswitch_sa.email}"
}

resource "google_project_iam_member" "killswitch_viewer" {
  project = var.GCP_PROJECT_ID
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.killswitch_sa.email}"
}

# -------------------------------------------------------
# Cloud Function source bucket
# -------------------------------------------------------
resource "google_storage_bucket" "function_source" {
  name                        = "${var.GCP_PROJECT_ID}-killswitch-source"
  location                    = "EU"
  force_destroy               = true
  uniform_bucket_level_access = true

  depends_on = [google_project_service.apis]
}

data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/tmp/killswitch.zip"
}

resource "google_storage_bucket_object" "function_source" {
  name   = "killswitch-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# -------------------------------------------------------
# Cloud Function
# -------------------------------------------------------
resource "google_cloudfunctions2_function" "killswitch" {
  name     = "billing-killswitch"
  location = var.GCP_REGION

  build_config {
    runtime     = "python311"
    entry_point = "stop_billing"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.killswitch_sa.email

    environment_variables = {
      GOOGLE_CLOUD_PROJECT      = var.GCP_PROJECT_ID
      SIMULATE_DEACTIVATION     = "false"
    }
  }

  event_trigger {
    trigger_region = var.GCP_REGION
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.billing_alerts.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  depends_on = [google_project_service.apis]
}