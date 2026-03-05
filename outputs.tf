output "killswitch_function_name" {
  value = google_cloudfunctions2_function.killswitch.name
}

output "pubsub_topic" {
  value = google_pubsub_topic.billing_alerts.name
}
