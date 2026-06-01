#!/usr/bin/env python3
"""Railway API helper — create volume and set variables via GraphQL."""
import urllib.request
import urllib.error
import json
import os
import sys

# Read token from railway config
config_path = os.path.join(os.environ["USERPROFILE"], ".railway", "config.json")
with open(config_path) as f:
    config = json.load(f)

TOKEN = config["user"]["accessToken"]
PROJECT_ID = "8a25cb4b-f36e-49ee-aa71-b349d44a1061"
SERVICE_ID = "7defa0b8-c329-44da-9944-3bf3afe8164d"
API_URL = "https://backboard.railway.app/graphql/v2"

def graphql(query, variables=None):
    data = json.dumps({"query": query, "variables": variables or {}}).encode()
    req = urllib.request.Request(
        API_URL,
        data=data,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json"
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"HTTP {e.code}: {body}", file=sys.stderr)
        return {"errors": [{"message": body}]}
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return None

def run(desc, query, variables=None):
    print(f"\n{'='*60}")
    print(f"  {desc}")
    print(f"{'='*60}")
    result = graphql(query, variables)
    if result:
        print(json.dumps(result, indent=2))
    return result

if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "list"

    if action == "list":
        run("List volumes", """
        {
          project(id: "%s") {
            volumes {
              edges {
                node {
                  id
                  name
                }
              }
            }
          }
        }
        """ % PROJECT_ID)

    elif action == "create-volume":
        run("Create volume /hermes-data", """
        mutation {
          volumeCreate(
            input: {
              projectId: "%s"
              serviceId: "%s"
              mountPath: "/hermes-data"
              name: "hermes-data"
            }
          ) {
            id
            name
            mountPath
          }
        }
        """ % (PROJECT_ID, SERVICE_ID))

    elif action == "set-var":
        # railway_api.py set-var KEY VALUE
        key = sys.argv[2] if len(sys.argv) > 2 else ""
        value = sys.argv[3] if len(sys.argv) > 3 else ""
        if not key or not value:
            print("Usage: railway_api.py set-var KEY VALUE")
            sys.exit(1)
        run(f"Set variable {key}", """
        mutation {
          variableUpsert(
            input: {
              projectId: "%s"
              serviceId: "%s"
              key: "%s"
              value: "%s"
            }
          ) {
            id
            key
            value
          }
        }
        """ % (PROJECT_ID, SERVICE_ID, key, value))

    elif action == "redeploy":
        run("Trigger redeploy", """
        mutation {
          deploymentRedeploy(
            serviceId: "%s"
            environmentId: "343005ba-7e1d-42e1-8e20-ec9aad9c4503"
          ) {
            id
            status
          }
        }
        """ % SERVICE_ID)

    else:
        print(f"Unknown action: {action}")
        print("Actions: list, create-volume, set-var, redeploy")
