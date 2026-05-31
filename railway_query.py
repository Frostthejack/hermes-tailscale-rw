import json, urllib.request, urllib.error, os

config_path = os.path.join(os.path.expanduser("~"), ".railway", "config.json")
with open(config_path) as f:
    config = json.load(f)

token = config["user"]["accessToken"]
service_id = list(config["projects"].values())[0]["service"]

query = '{"query":"{ deployments(serviceId: \"' + service_id + '\", first: 5) { edges { node { id status createdAt buildStatus } } } }"}'

data = query.encode()
req = urllib.request.Request(
    "https://backboard.railway.app/graphql/v2",
    data=data,
    headers={
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json"
    }
)

try:
    resp = urllib.request.urlopen(req, timeout=15)
    result = json.loads(resp.read())
    print(json.dumps(result, indent=2)[:3000])
except urllib.error.HTTPError as e:
    print("HTTP", e.code, ":", e.read().decode()[:500])
except Exception as e:
    print("Error:", e)
