#!/usr/bin/env python3
"""Create product hosted Maven repos and attach them to maven-public. Idempotent."""
from __future__ import print_function

import json
import os
import sys

try:
    from urllib.error import HTTPError
    from urllib.request import Request, urlopen
except ImportError:
    from urllib2 import HTTPError, Request, urlopen


def request(method, url, user, password, body=None):
    import base64

    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    token = base64.b64encode(("%s:%s" % (user, password)).encode("ascii")).decode("ascii")
    headers["Authorization"] = "Basic " + token
    req = Request(url, data=data, headers=headers, method=method)
    try:
        response = urlopen(req)
        raw = response.read()
        if not raw:
            return response.getcode(), None
        return response.getcode(), json.loads(raw.decode("utf-8"))
    except HTTPError as error:
        raw = error.read()
        payload = None
        if raw:
            try:
                payload = json.loads(raw.decode("utf-8"))
            except ValueError:
                payload = raw.decode("utf-8")
        return error.code, payload


def hosted_body(name, version_policy):
    return {
        "name": name,
        "online": True,
        "storage": {
            "blobStoreName": "default",
            "strictContentTypeValidation": True,
            "writePolicy": "ALLOW",
        },
        "maven": {
            "versionPolicy": version_policy,
            "layoutPolicy": "STRICT",
        },
    }


def repo_names(listing):
    names = set()
    for item in listing or []:
        names.add(item.get("name"))
    return names


def main():
    base = os.environ.get("NEXUS_URL", "http://127.0.0.1:8081").rstrip("/")
    user = os.environ.get("NEXUS_USERNAME", "admin")
    password = os.environ["NEXUS_PASSWORD"]
    api = base + "/service/rest/v1"

    code, listing = request("GET", api + "/repositories", user, password)
    if code != 200:
        sys.stderr.write("Could not list Nexus repositories: %s %s\n" % (code, listing))
        return 1
    existing = repo_names(listing)

    wanted = (
        ("products-releases", "RELEASE"),
        ("products-snapshots", "SNAPSHOT"),
    )
    for name, policy in wanted:
        if name in existing:
            print("Nexus hosted repository already exists:", name)
            continue
        code, payload = request(
            "POST", api + "/repositories/maven/hosted", user, password, hosted_body(name, policy)
        )
        if code not in (200, 201, 204):
            sys.stderr.write("Could not create %s: %s %s\n" % (name, code, payload))
            return 1
        print("Created Nexus hosted repository:", name)

    code, group = request("GET", api + "/repositories/maven/group/maven-public", user, password)
    if code != 200:
        sys.stderr.write("Could not read maven-public: %s %s\n" % (code, group))
        return 1

    members = list(group.get("group", {}).get("memberNames") or [])
    for name, _policy in wanted:
        if name not in members:
            members.append(name)
    storage = group.get("storage") or {}
    group_body = {
        "name": "maven-public",
        "online": True,
        "storage": {
            "blobStoreName": storage.get("blobStoreName", "default"),
            "strictContentTypeValidation": True,
        },
        "group": {"memberNames": members},
    }
    code, payload = request(
        "PUT", api + "/repositories/maven/group/maven-public", user, password, group_body
    )
    if code not in (200, 204):
        sys.stderr.write("Could not update maven-public: %s %s\n" % (code, payload))
        return 1
    print("maven-public members:", ", ".join(members))

    code, payload = request(
        "PUT",
        api + "/security/anonymous",
        user,
        password,
        {
            "enabled": True,
            "userId": "anonymous",
            "realmName": "NexusAuthorizingRealm",
        },
    )
    if code not in (200, 204):
        print("Anonymous access left unchanged:", code, payload)
    else:
        print("Anonymous read enabled")

    for hosted in ("maven-releases", "maven-snapshots"):
        code, body = request("GET", api + "/repositories/maven/hosted/" + hosted, user, password)
        if code != 200:
            print("Skip write-policy update for", hosted, code)
            continue
        storage = body.get("storage") or {}
        maven = body.get("maven") or {}
        hosted_update = {
            "name": hosted,
            "online": True,
            "storage": {
                "blobStoreName": storage.get("blobStoreName", "default"),
                "strictContentTypeValidation": True,
                "writePolicy": "ALLOW",
            },
            "maven": maven,
        }
        code, payload = request(
            "PUT",
            api + "/repositories/maven/hosted/" + hosted,
            user,
            password,
            hosted_update,
        )
        if code not in (200, 204):
            print("Could not allow redeploy on", hosted, code, payload)
        else:
            print("Redeploy allowed on", hosted)

    return 0


if __name__ == "__main__":
    sys.exit(main())
