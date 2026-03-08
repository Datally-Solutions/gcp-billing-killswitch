import base64
import json
import os
import urllib.request

from cloudevents.http import CloudEvent
import functions_framework
from googleapiclient import discovery

# TODO: Set to False after validating with a test budget
# When True, the function logs what it would do but does NOT disable billing
SIMULATE = os.getenv("SIMULATE_DEACTIVATION", "true").lower() == "true"


def _get_project_id() -> str:
    project_id = os.getenv("GOOGLE_CLOUD_PROJECT")
    if project_id is not None:
        return project_id
    url = "http://metadata.google.internal/computeMetadata/v1/project/project-id"
    req = urllib.request.Request(url)
    req.add_header("Metadata-Flavor", "Google")
    return urllib.request.urlopen(req).read().decode()


def _is_billing_enabled(project_name: str, billing_client) -> bool:
    try:
        res = billing_client.projects().getBillingInfo(name=project_name).execute()
        return res.get("billingEnabled", False)
    except Exception as e:
        print(f"Error checking billing status: {e}")
        return False


def _disable_billing(project_name: str, billing_client) -> None:
    try:
        billing_client.projects().updateBillingInfo(
            name=project_name, body={"billingAccountName": ""}
        ).execute()
        print(f"Billing disabled for {project_name}")
    except Exception as e:
        print(f"Error disabling billing: {e}")
        raise


@functions_framework.cloud_event
def stop_billing(cloud_event: CloudEvent) -> None:
    pubsub_data = base64.b64decode(cloud_event.data["message"]["data"]).decode("utf-8")

    budget_data = json.loads(pubsub_data)
    print(f"Budget notification received: {budget_data}")

    cost_amount = budget_data.get("costAmount", 0)
    budget_amount = budget_data.get("budgetAmount", 0)

    if cost_amount <= budget_amount:
        print(
            f"Cost ({cost_amount}) within budget ({budget_amount}). No action needed."
        )
        return

    project_id = _get_project_id()
    project_name = f"projects/{project_id}"
    billing = discovery.build("cloudbilling", "v1", cache_discovery=False)

    if not _is_billing_enabled(project_name, billing):
        print("Billing already disabled.")
        return

    if SIMULATE:
        print(
            f"SIMULATE=True — would disable billing for {project_name}. "
            f"Cost: {cost_amount} > Budget: {budget_amount}. "
            "Set SIMULATE=False to enable real kill switch."
        )
        return

    print(f"Cost ({cost_amount}) exceeds budget ({budget_amount}). Disabling billing!")
    _disable_billing(project_name, billing)
