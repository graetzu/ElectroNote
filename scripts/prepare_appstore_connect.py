import os
import sys
import time
import json
import base64
import plistlib
import jwt
import requests

def extract_profile_info(prof_bytes):
    start = prof_bytes.find(b"<?xml")
    end = prof_bytes.find(b"</plist>")
    if start != -1 and end != -1:
        end += len(b"</plist>")
        try:
            data = plistlib.loads(prof_bytes[start:end])
            return data.get("UUID"), data.get("Name"), data.get("Entitlements", {}).get("application-identifier")
        except Exception as e:
            print(f"Error parsing profile XML: {e}")
    return None, None, None

def install_profile(uuid, content_bytes):
    prov_dir = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(prov_dir, exist_ok=True)
    prov_path = os.path.join(prov_dir, f"{uuid}.mobileprovision")
    with open(prov_path, "wb") as f:
        f.write(content_bytes)
    print(f"Installed Provisioning Profile {uuid} to {prov_path}")

    gh_env = os.environ.get("GITHUB_ENV")
    if gh_env and os.path.exists(gh_env):
        with open(gh_env, "a") as f:
            f.write(f"PROVISIONING_PROFILE_UUID={uuid}\n")
    print(f"Exported PROVISIONING_PROFILE_UUID={uuid}")

def main():
    # 0. Check if a base64 encoded provisioning profile secret is provided directly
    profile_b64 = os.environ.get("IOS_PROVISIONING_PROFILE_BASE64")
    if profile_b64:
        print("--> Found IOS_PROVISIONING_PROFILE_BASE64 in environment...")
        try:
            prof_bytes = base64.b64decode(profile_b64)
            uuid, name, app_id = extract_profile_info(prof_bytes)
            if uuid:
                print(f"Successfully decoded profile: {name} ({uuid}), AppID: {app_id}")
                install_profile(uuid, prof_bytes)
            else:
                print("Warning: Could not extract UUID from IOS_PROVISIONING_PROFILE_BASE64")
        except Exception as e:
            print(f"Warning: Failed to decode IOS_PROVISIONING_PROFILE_BASE64: {e}")

    key_id = os.environ.get("ASC_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer_id:
        print("Missing ASC_KEY_ID or ASC_ISSUER_ID")
        return

    key_path = os.path.expanduser(f"~/.private_keys/AuthKey_{key_id}.p8")
    if not os.path.exists(key_path):
        print(f"Private key not found at {key_path}")
        return

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

    # 1. Inspect existing Bundle IDs
    print("--> Inspecting registered Bundle IDs in Apple Developer account...")
    res = session.get(f"{BASE_URL}/bundleIds?limit=50")
    all_bids = res.json().get("data", []) if res.status_code == 200 else []
    print(f"Found {len(all_bids)} registered bundle ID(s):")
    bundle_id_res_id = None
    for b in all_bids:
        bid = b["attributes"].get("identifier", "")
        b_name = b["attributes"].get("name", "")
        print(f"  - [{b['id']}] {bid} ('{b_name}')")
        if bid.lower() == bundle_identifier.lower():
            bundle_id_res_id = b["id"]

    if not bundle_id_res_id:
        print(f"Registering new Bundle ID: {bundle_identifier}...")
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
            print(f"Bundle ID creation response ({create_res.status_code}): {create_res.text}")

    # 2. Inspect existing App records
    print("--> Inspecting App records in App Store Connect...")
    apps_res = session.get(f"{BASE_URL}/apps?limit=50")
    all_apps = apps_res.json().get("data", []) if apps_res.status_code == 200 else []
    print(f"Found {len(all_apps)} app(s) in App Store Connect:")
    for a in all_apps:
        print(f"  - [{a['id']}] {a['attributes'].get('name')} (bundleId: {a['attributes'].get('bundleId')})")

    # 3. Inspect Distribution Certificates
    print("--> Inspecting Distribution Certificates...")
    cert_res = session.get(f"{BASE_URL}/certificates?filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION")
    certs = cert_res.json().get("data", []) if cert_res.status_code == 200 else []
    print(f"Found {len(certs)} distribution certificate(s):")
    for c in certs:
        print(f"  - [{c['id']}] {c['attributes'].get('name')} (expires: {c['attributes'].get('expirationDate')})")
    cert_id = certs[0]["id"] if certs else None

    # 4. Inspect Provisioning Profiles
    print("--> Inspecting Provisioning Profiles...")
    prof_res = session.get(f"{BASE_URL}/profiles?filter[profileType]=IOS_APP_STORE&fields[profiles]=name,profileState,profileType,uuid,profileContent&include=bundleId&limit=50")
    profs = prof_res.json().get("data", []) if prof_res.status_code == 200 else []
    print(f"Found {len(profs)} iOS App Store provisioning profile(s):")
    matching_prof = None

    for p in profs:
        p_name = p["attributes"].get("name", "")
        p_state = p["attributes"].get("profileState", "")
        p_uuid = p["attributes"].get("uuid", "")
        b_rel = p.get("relationships", {}).get("bundleId", {}).get("data", {})
        print(f"  - [{p['id']}] '{p_name}' | UUID: {p_uuid} | State: {p_state} | Bundle Rel: {b_rel.get('id')}")

        is_matching = False
        if bundle_id_res_id and b_rel.get("id") == bundle_id_res_id:
            is_matching = True
        elif bundle_identifier.lower() in p_name.lower() or "electronote" in p_name.lower():
            is_matching = True

        if is_matching and p_state == "ACTIVE" and not matching_prof:
            matching_prof = p
            print(f"  ==> Selected active matching profile: {p_name} ({p_uuid})")

    # 5. Create profile if bundle ID and cert exist but no active profile found
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
            print(f"Provisioning profile creation response ({p_create_res.status_code}): {p_create_res.text}")

    # 6. Install downloaded profile if available
    if matching_prof:
        p_uuid = matching_prof["attributes"]["uuid"]
        p_content = matching_prof["attributes"].get("profileContent")
        if not p_content:
            print(f"Fetching full profile resource for {p_uuid}...")
            single_res = session.get(f"{BASE_URL}/profiles/{matching_prof['id']}")
            if single_res.status_code == 200:
                p_content = single_res.json().get("data", {}).get("attributes", {}).get("profileContent")
        if p_content:
            install_profile(p_uuid, base64.b64decode(p_content))
        else:
            print("Warning: Could not obtain profileContent for profile")

    print("--> App Store Connect inspection complete.")

if __name__ == "__main__":
    main()
