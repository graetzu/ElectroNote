import os
import sys
import time
import json
import base64
import jwt
import requests

def main():
    key_id = os.environ.get("ASC_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer_id:
        print("Missing ASC_KEY_ID or ASC_ISSUER_ID")
        sys.exit(1)

    key_path = os.path.expanduser(f"~/.private_keys/AuthKey_{key_id}.p8")
    if not os.path.exists(key_path):
        print(f"Private key not found at {key_path}")
        sys.exit(1)

    with open(key_path, "r") as f:
        private_key = f.read()

    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1"
    }
    headers = {
        "alg": "ES256",
        "kid": key_id,
        "typ": "JWT"
    }

    token = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
    if isinstance(token, bytes):
        token = token.decode("utf-8")
    session = requests.Session()
    session.headers.update({
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    })

    BASE_URL = "https://api.appstoreconnect.apple.com/v1"
    bundle_identifier = "de.graetz.electronote"
    app_name = "ElectroNote"

    # 1. Check or create Bundle ID
    print(f"--> Checking Bundle ID: {bundle_identifier}...")
    res = session.get(f"{BASE_URL}/bundleIds?filter[identifier]={bundle_identifier}")
    data = res.json().get("data", [])
    bundle_id_res_id = None

    if not data:
        print(f"Registering Bundle ID: {bundle_identifier}...")
        body = {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": bundle_identifier,
                    "name": app_name,
                    "platform": "IOS"
                }
            }
        }
        create_res = session.post(f"{BASE_URL}/bundleIds", json=body)
        if create_res.status_code in [200, 201]:
            bundle_id_res_id = create_res.json()["data"]["id"]
            print(f"Bundle ID created with ID: {bundle_id_res_id}")
        else:
            print(f"Warning: Could not create bundle ID ({create_res.status_code}): {create_res.text}")
    else:
        bundle_id_res_id = data[0]["id"]
        print(f"Found existing Bundle ID with ID: {bundle_id_res_id}")

    # 2. Check or create App Record in App Store Connect
    print(f"--> Checking App in App Store Connect: {app_name} ({bundle_identifier})...")
    res = session.get(f"{BASE_URL}/apps?filter[bundleId]={bundle_identifier}")
    apps_data = res.json().get("data", [])

    if not apps_data and bundle_id_res_id:
        print(f"Creating App Record in App Store Connect...")
        body = {
            "data": {
                "type": "apps",
                "attributes": {
                    "name": app_name,
                    "bundleId": bundle_identifier,
                    "primaryLocale": "de-DE",
                    "sku": bundle_identifier
                }
            }
        }
        create_app_res = session.post(f"{BASE_URL}/apps", json=body)
        if create_app_res.status_code in [200, 201]:
            app_id = create_app_res.json()["data"]["id"]
            print(f"App created successfully with ID: {app_id}")
        else:
            print(f"App creation note ({create_app_res.status_code}): {create_app_res.text}")
    elif apps_data:
        print(f"App Record exists with ID: {apps_data[0]['id']}")

    # 3. Find Distribution Certificate
    print("--> Checking Distribution Certificates...")
    cert_res = session.get(f"{BASE_URL}/certificates?filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION")
    certs = cert_res.json().get("data", [])
    print(f"Found {len(certs)} distribution certificate(s).")
    cert_id = certs[0]["id"] if certs else None

    # 4. Check or create App Store Provisioning Profile
    print("--> Checking Provisioning Profiles...")
    prof_res = session.get(f"{BASE_URL}/profiles?filter[profileType]=IOS_APP_STORE&include=bundleId")
    profs = prof_res.json().get("data", [])
    matching_prof = None

    for p in profs:
        p_name = p["attributes"].get("name", "")
        p_state = p["attributes"].get("profileState", "")
        b_rel = p.get("relationships", {}).get("bundleId", {}).get("data", {})
        if (b_rel.get("id") == bundle_id_res_id or bundle_identifier in p_name or "ElectroNote" in p_name) and p_state == "ACTIVE":
            matching_prof = p
            print(f"Found matching active profile: {p_name} ({p['attributes'].get('uuid')})")
            break

    if not matching_prof and bundle_id_res_id and cert_id:
        print("Creating new App Store Provisioning Profile...")
        body = {
            "data": {
                "type": "profiles",
                "attributes": {
                    "name": f"ElectroNote AppStore Profile",
                    "profileType": "IOS_APP_STORE"
                },
                "relationships": {
                    "bundleId": {
                        "data": {"type": "bundleIds", "id": bundle_id_res_id}
                    },
                    "certificates": {
                        "data": [{"type": "certificates", "id": cert_id}]
                    }
                }
            }
        }
        p_create_res = session.post(f"{BASE_URL}/profiles", json=body)
        if p_create_res.status_code in [200, 201]:
            matching_prof = p_create_res.json()["data"]
            print(f"Provisioning profile created: {matching_prof['attributes']['name']}")
        else:
            print(f"Provisioning profile creation response: {p_create_res.text}")

    if matching_prof:
        p_uuid = matching_prof["attributes"]["uuid"]
        p_content = matching_prof["attributes"]["profileContent"]
        prov_dir = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
        os.makedirs(prov_dir, exist_ok=True)
        prov_path = os.path.join(prov_dir, f"{p_uuid}.mobileprovision")
        with open(prov_path, "wb") as f:
            f.write(base64.b64decode(p_content))
        print(f"Installed Provisioning Profile {p_uuid} to {prov_path}")

        gh_env = os.environ.get("GITHUB_ENV")
        if gh_env and os.path.exists(gh_env):
            with open(gh_env, "a") as f:
                f.write(f"PROVISIONING_PROFILE_UUID={p_uuid}\n")

    print("--> App Store Connect preparation complete.")

if __name__ == "__main__":
    main()
