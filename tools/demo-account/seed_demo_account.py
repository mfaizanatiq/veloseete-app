#!/usr/bin/env python3
"""
Create / refresh the Veloseete Apple review demo account in Firebase.

Multi-vehicle “pro” garage: active cars with full fuels/drives/service history,
plus one archived car to demo restore.

Usage:
    python3 tools/demo-account/seed_demo_account.py
    python3 tools/demo-account/seed_demo_account.py --project velocity-5e576
"""

from __future__ import annotations

import argparse
import json
import plistlib
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIGSTORE = Path.home() / ".config/configstore/firebase-tools.json"
CLI_CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
CLI_CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi"

DEMO_EMAIL = "demo@veloseete.app"
DEMO_PASSWORD = "VeloseeteDemo2026!"
DEMO_NAME = "Demo Driver"
PRIMARY_VEHICLE_ID = "demo_vehicle_pearl"

COLLECTIONS = ("vehicles", "fuelLogs", "serviceLogs", "trips", "productFeedback", "featureRequests")

# Dubai map anchors (lat, lng).
DUBAI = {
    "marina": (25.0772, 55.1390),
    "jbr": (25.0782, 55.1340),
    "jlt": (25.0694, 55.1428),
    "dic": (25.0948, 55.1562),
    "media_city": (25.0922, 55.1520),
    "moe": (25.1180, 55.2000),
    "barsha": (25.1105, 55.1995),
    "szr_mall": (25.1540, 55.2410),
    "business_bay": (25.1850, 55.2650),
    "downtown": (25.1972, 55.2744),
    "difc": (25.2110, 55.2800),
    "city_walk": (25.2080, 55.2590),
    "jvc": (25.0580, 55.2100),
    "motor_city": (25.0450, 55.2350),
    "palm_trunk": (25.1120, 55.1390),
    "atlantis": (25.1304, 55.1173),
    "dxb_t3": (25.2532, 55.3657),
    "garhoud": (25.2450, 55.3400),
    "deira": (25.2700, 55.3000),
    "expo": (24.9600, 55.1500),
    "arabian_ranches": (25.0520, 55.2700),
    "al_quoz": (25.1300, 55.2300),
}


def post_json(url: str, payload: dict, token: str | None = None) -> dict:
    body = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def cli_access_token() -> str:
    refresh = json.loads(CONFIGSTORE.read_text())["tokens"]["refresh_token"]
    result = post_json("https://oauth2.googleapis.com/token", {
        "grant_type": "refresh_token",
        "refresh_token": refresh,
        "client_id": CLI_CLIENT_ID,
        "client_secret": CLI_CLIENT_SECRET,
    })
    return result["access_token"]


def load_api_key() -> str:
    plist = ROOT / "Veloseete/GoogleService-Info.plist"
    return plistlib.loads(plist.read_bytes())["API_KEY"]


def auth_session(api_key: str) -> tuple[str, str]:
    base = "https://identitytoolkit.googleapis.com/v1/accounts"
    payload = {"email": DEMO_EMAIL, "password": DEMO_PASSWORD, "returnSecureToken": True}
    try:
        result = post_json(f"{base}:signUp?key={api_key}", payload)
    except urllib.error.HTTPError as err:
        body = json.loads(err.read().decode())
        if body.get("error", {}).get("message") not in {"EMAIL_EXISTS", "EMAIL_ALREADY_IN_USE"}:
            raise
        result = post_json(f"{base}:signInWithPassword?key={api_key}", payload)
    post_json(
        f"{base}:update?key={api_key}",
        {"idToken": result["idToken"], "displayName": DEMO_NAME, "returnSecureToken": False},
    )
    return result["localId"], result["idToken"]


def firestore_token(api_key: str) -> tuple[str, str]:
    uid, id_token = auth_session(api_key)
    if CONFIGSTORE.exists():
        try:
            return uid, cli_access_token()
        except urllib.error.HTTPError:
            pass
    return uid, id_token


def field(value) -> dict:
    if value is None:
        return {"nullValue": None}
    if isinstance(value, bool):
        return {"booleanValue": value}
    if isinstance(value, int):
        return {"integerValue": str(value)}
    if isinstance(value, float):
        return {"doubleValue": value}
    if isinstance(value, datetime):
        return {"timestampValue": value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    if isinstance(value, dict):
        return {"mapValue": {"fields": {k: field(v) for k, v in value.items()}}}
    if isinstance(value, list):
        return {"arrayValue": {"values": [field(v) for v in value]}}
    return {"stringValue": str(value)}


def doc_fields(data: dict) -> dict:
    return {k: field(v) for k, v in data.items()}


def run_query(token: str, project: str, collection: str, user_id: str) -> list[str]:
    url = f"https://firestore.googleapis.com/v1/projects/{project}/databases/(default)/documents:runQuery"
    payload = {
        "structuredQuery": {
            "from": [{"collectionId": collection}],
            "where": {
                "fieldFilter": {
                    "field": {"fieldPath": "userId"},
                    "op": "EQUAL",
                    "value": {"stringValue": user_id},
                }
            },
        }
    }
    rows = post_json(url, payload, token)
    return [row["document"]["name"] for row in rows if row.get("document")]


def batch_delete(token: str, doc_names: list[str]) -> None:
    if not doc_names:
        return
    project = doc_names[0].split("/")[1]
    url = f"https://firestore.googleapis.com/v1/projects/{project}/databases/(default)/documents:batchWrite"
    writes = [{"delete": name} for name in doc_names]
    for start in range(0, len(writes), 500):
        post_json(url, {"writes": writes[start:start + 500]}, token)


def wipe_user_data(token: str, project: str, user_id: str) -> None:
    for collection in COLLECTIONS:
        batch_delete(token, run_query(token, project, collection, user_id))
    batch_delete(token, [f"projects/{project}/databases/(default)/documents/users/{user_id}"])


def write_doc(token: str, project: str, collection: str, doc_id: str, data: dict) -> None:
    url = (
        f"https://firestore.googleapis.com/v1/projects/{project}/databases/(default)/"
        f"documents/{collection}?documentId={doc_id}"
    )
    req = urllib.request.Request(
        url,
        data=json.dumps({"fields": doc_fields(data)}).encode(),
        method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req):
        pass


def route_through_waypoints(waypoints: list[tuple[float, float]], points_per_leg: int = 6) -> list[dict]:
    if len(waypoints) < 2:
        return []
    coords: list[dict] = []
    for index in range(len(waypoints) - 1):
        s_lat, s_lng = waypoints[index]
        e_lat, e_lng = waypoints[index + 1]
        leg_points = points_per_leg + 1 if index == 0 else points_per_leg
        for step in range(leg_points):
            if index > 0 and step == 0:
                continue
            t = step / max(leg_points - 1, 1)
            coords.append({
                "lat": round(s_lat + (e_lat - s_lat) * t, 6),
                "lng": round(s_lng + (e_lng - s_lng) * t, 6),
            })
    return coords


def seed_fills(
    token: str,
    project: str,
    user_id: str,
    vehicle_id: str,
    currency: str,
    now: datetime,
    *,
    start_odo: float,
    start_days_ago: int,
    count: int,
    km_between: float,
    litres: float,
    price_per_l: float,
    stations: list[tuple[str, float, float]],
    day_step: int = 14,
) -> float:
    """Write ascending full-tank fills; returns final odometer."""
    odo = start_odo
    for index in range(count):
        days_ago = start_days_ago - index * day_step
        station, lat, lng = stations[index % len(stations)]
        total = round(litres * price_per_l, 2)
        write_doc(token, project, "fuelLogs", uuid.uuid4().hex[:16], {
            "userId": user_id,
            "vehicle_id": vehicle_id,
            "odometer_reading": odo,
            "fuel_volume": litres,
            "price_per_unit": price_per_l,
            "total_cost": total,
            "currency": currency,
            "is_full_tank": True,
            "timestamp": now - timedelta(days=max(days_ago, 1), hours=10 + index),
            "station_name": station,
            "station_lat": lat,
            "station_lng": lng,
            "createdAt": now - timedelta(days=max(days_ago, 1)),
            "updatedAt": now - timedelta(days=max(days_ago, 1)),
        })
        if index < count - 1:
            odo += km_between
    return odo


def seed_trip(
    token: str,
    project: str,
    user_id: str,
    vehicle_id: str,
    now: datetime,
    *,
    days_ago: int,
    km: float,
    duration_min: int,
    avg: float,
    max_speed: float,
    waypoint_keys: list[str],
    source: str,
) -> None:
    started = now - timedelta(days=days_ago, hours=8)
    ended = started + timedelta(minutes=duration_min)
    waypoints = [DUBAI[key] for key in waypoint_keys]
    route = route_through_waypoints(waypoints, points_per_leg=7)
    s_lat, s_lng = waypoints[0]
    e_lat, e_lng = waypoints[-1]
    write_doc(token, project, "trips", uuid.uuid4().hex[:16], {
        "userId": user_id,
        "vehicle_id": vehicle_id,
        "startedAt": started,
        "endedAt": ended,
        "distanceKm": km,
        "durationSec": float(duration_min * 60),
        "avgSpeedKmh": avg,
        "maxSpeedKmh": max_speed,
        "route": route,
        "startCoord": {"lat": s_lat, "lng": s_lng},
        "endCoord": {"lat": e_lat, "lng": e_lng},
        "source": source,
        "createdAt": started,
        "updatedAt": ended,
    })


def seed_service(
    token: str,
    project: str,
    user_id: str,
    vehicle_id: str,
    currency: str,
    now: datetime,
    *,
    days_ago: int,
    odo: float,
    kind: str,
    desc: str,
    cost: float,
    next_odo: float | None = None,
    next_days: int | None = None,
) -> None:
    data = {
        "userId": user_id,
        "vehicle_id": vehicle_id,
        "timestamp": now - timedelta(days=days_ago),
        "odometer_reading": odo,
        "service_type": kind,
        "description": desc,
        "cost": cost,
        "currency": currency,
        "createdAt": now - timedelta(days=days_ago),
        "updatedAt": now - timedelta(days=days_ago),
    }
    if next_odo is not None:
        data["next_service_odometer"] = next_odo
    if next_days is not None:
        data["next_service_date"] = now + timedelta(days=next_days)
    write_doc(token, project, "serviceLogs", uuid.uuid4().hex[:16], data)


def seed_demo_data(token: str, project: str, user_id: str) -> None:
    now = datetime.now(timezone.utc)
    currency = "AED"

    write_doc(token, project, "users", user_id, {
        "userId": user_id,
        "profile": {
            "userName": DEMO_NAME,
            "defaultCurrency": currency,
            "defaultDistanceUnit": "km",
            "createdAt": now - timedelta(days=400),
            "updatedAt": now,
        },
        "currentVehicleId": PRIMARY_VEHICLE_ID,
        "metadata": {"lastSync": now},
    })

    vehicles = [
        {
            "id": "demo_vehicle_pearl",
            "nickname": "Pearl",
            "make": "Toyota",
            "model": "Camry Hybrid LE",
            "fuelType": "hybrid",
            "icon": "sedan",
            "paintColor": "blue",
            "tank": 50.0,
            "created_days": 380,
            "archived": False,
        },
        {
            "id": "demo_vehicle_sandstorm",
            "nickname": "Sandstorm",
            "make": "Nissan",
            "model": "Patrol LE",
            "fuelType": "diesel",
            "icon": "suv",
            "paintColor": "beige",
            "tank": 80.0,
            "created_days": 340,
            "archived": False,
        },
        {
            "id": "demo_vehicle_flash",
            "nickname": "Flash",
            "make": "BMW",
            "model": "330i M Sport",
            "fuelType": "petrol",
            "icon": "sport",
            "paintColor": "red",
            "tank": 59.0,
            "created_days": 260,
            "archived": False,
        },
        {
            "id": "demo_vehicle_spark",
            "nickname": "Spark",
            "make": "Honda",
            "model": "Civic LX",
            "fuelType": "petrol",
            "icon": "hatch",
            "paintColor": "silver",
            "tank": 47.0,
            "created_days": 720,
            "archived": True,
            "archived_days": 45,
        },
    ]

    stations = [
        ("ENOC Sheikh Zayed Rd", 25.1540, 55.2410),
        ("ADNOC Dubai Marina", 25.0765, 55.1375),
        ("EPPCO Al Barsha", 25.1120, 55.1980),
        ("ENOC Business Bay", 25.1880, 55.2680),
        ("ADNOC JVC", 25.0560, 55.2080),
        ("ENOC Deira", 25.2650, 55.3050),
        ("ADNOC Motor City", 25.0450, 55.2350),
    ]

    final_odos: dict[str, float] = {}

    # —— Pearl: daily hybrid commuter ——
    final_odos["demo_vehicle_pearl"] = seed_fills(
        token, project, user_id, "demo_vehicle_pearl", currency, now,
        start_odo=38420, start_days_ago=112, count=8, km_between=780,
        litres=42.0, price_per_l=3.08, stations=stations, day_step=13,
    )
    pearl_trips = [
        (2, 22.4, 38, 35, 78, ["marina", "jlt", "barsha", "szr_mall", "business_bay", "downtown"], "auto"),
        (4, 14.8, 26, 34, 72, ["jbr", "marina", "moe", "business_bay", "difc"], "auto"),
        (7, 5.6, 14, 24, 48, ["dic", "media_city", "marina"], "manual"),
        (9, 18.2, 34, 32, 68, ["downtown", "city_walk", "szr_mall", "marina", "palm_trunk", "atlantis"], "auto"),
        (14, 8.4, 18, 28, 58, ["jvc", "barsha", "moe"], "auto"),
        (19, 11.9, 22, 32, 85, ["dxb_t3", "garhoud", "deira"], "auto"),
        (24, 16.5, 30, 33, 74, ["marina", "szr_mall", "downtown", "difc"], "auto"),
        (29, 9.2, 20, 28, 62, ["business_bay", "city_walk", "marina"], "auto"),
        (35, 21.0, 36, 35, 80, ["jlt", "barsha", "moe", "al_quoz", "dic"], "auto"),
        (42, 7.8, 17, 27, 55, ["marina", "jbr", "media_city"], "auto"),
        (52, 13.6, 28, 29, 70, ["downtown", "business_bay", "marina"], "auto"),
        (68, 10.4, 24, 26, 64, ["jvc", "motor_city", "barsha"], "auto"),
        (85, 19.8, 40, 30, 76, ["marina", "palm_trunk", "atlantis", "marina"], "auto"),
        (98, 6.5, 15, 26, 50, ["dic", "marina"], "manual"),
    ]
    for args in pearl_trips:
        seed_trip(token, project, user_id, "demo_vehicle_pearl", now,
                  days_ago=args[0], km=args[1], duration_min=args[2], avg=args[3],
                  max_speed=args[4], waypoint_keys=args[5], source=args[6])
    for svc in [
        (70, 39650, "oil", "5W-30 synthetic + filter", 420.0, 47650, 150),
        (28, 42680, "tires", "Rotation + alignment check", 280.0, None, None),
        (8, 43420, "brakes", "Front pad inspection — still good", 150.0, 45420, 90),
    ]:
        seed_service(token, project, user_id, "demo_vehicle_pearl", currency, now,
                     days_ago=svc[0], odo=svc[1], kind=svc[2], desc=svc[3], cost=svc[4],
                     next_odo=svc[5], next_days=svc[6])

    # —— Sandstorm: diesel SUV, longer runs ——
    final_odos["demo_vehicle_sandstorm"] = seed_fills(
        token, project, user_id, "demo_vehicle_sandstorm", currency, now,
        start_odo=121800, start_days_ago=105, count=7, km_between=650,
        litres=78.0, price_per_l=3.15, stations=stations, day_step=14,
    )
    sand_trips = [
        (3, 48.2, 55, 52, 118, ["marina", "szr_mall", "expo", "arabian_ranches", "jvc"], "auto"),
        (8, 62.5, 68, 55, 125, ["downtown", "szr_mall", "expo", "al_quoz"], "auto"),
        (15, 38.0, 45, 51, 110, ["deira", "garhoud", "dxb_t3", "downtown"], "auto"),
        (22, 55.8, 62, 54, 122, ["jvc", "arabian_ranches", "expo", "marina"], "auto"),
        (31, 41.2, 48, 52, 115, ["marina", "palm_trunk", "atlantis", "szr_mall", "downtown"], "auto"),
        (40, 70.4, 75, 56, 130, ["downtown", "deira", "garhoud", "expo"], "auto"),
        (55, 44.6, 50, 54, 118, ["moe", "barsha", "al_quoz", "motor_city"], "auto"),
        (72, 58.0, 65, 54, 120, ["marina", "szr_mall", "business_bay", "difc"], "auto"),
        (90, 36.5, 42, 52, 108, ["jvc", "barsha", "moe"], "auto"),
    ]
    for args in sand_trips:
        seed_trip(token, project, user_id, "demo_vehicle_sandstorm", now,
                  days_ago=args[0], km=args[1], duration_min=args[2], avg=args[3],
                  max_speed=args[4], waypoint_keys=args[5], source=args[6])
    for svc in [
        (48, 124200, "oil", "Diesel service + fuel filter", 890.0, 129200, 120),
        (12, 127400, "tires", "All-terrain rotation", 420.0, None, None),
    ]:
        seed_service(token, project, user_id, "demo_vehicle_sandstorm", currency, now,
                     days_ago=svc[0], odo=svc[1], kind=svc[2], desc=svc[3], cost=svc[4],
                     next_odo=svc[5], next_days=svc[6])

    # —— Flash: sport sedan, shorter spirited drives ——
    final_odos["demo_vehicle_flash"] = seed_fills(
        token, project, user_id, "demo_vehicle_flash", currency, now,
        start_odo=58900, start_days_ago=98, count=7, km_between=480,
        litres=48.0, price_per_l=3.22, stations=stations, day_step=13,
    )
    flash_trips = [
        (1, 12.8, 18, 43, 98, ["marina", "jlt", "difc"], "auto"),
        (5, 8.2, 12, 41, 92, ["downtown", "city_walk", "business_bay"], "manual"),
        (10, 15.6, 22, 42, 105, ["difc", "downtown", "marina", "jbr"], "auto"),
        (16, 11.4, 16, 43, 100, ["marina", "palm_trunk", "marina"], "auto"),
        (23, 19.2, 28, 41, 112, ["business_bay", "szr_mall", "marina", "dic"], "auto"),
        (30, 7.5, 11, 41, 88, ["jbr", "marina"], "manual"),
        (38, 14.0, 20, 42, 102, ["marina", "barsha", "moe", "difc"], "auto"),
        (50, 10.8, 15, 43, 95, ["downtown", "difc", "business_bay"], "auto"),
        (65, 17.5, 25, 42, 108, ["marina", "szr_mall", "downtown"], "auto"),
        (82, 9.6, 14, 41, 90, ["media_city", "dic", "marina"], "auto"),
    ]
    for args in flash_trips:
        seed_trip(token, project, user_id, "demo_vehicle_flash", now,
                  days_ago=args[0], km=args[1], duration_min=args[2], avg=args[3],
                  max_speed=args[4], waypoint_keys=args[5], source=args[6])
    for svc in [
        (42, 59800, "oil", "BMW LL-14FE + micro filter", 780.0, 64800, 180),
        (6, 62100, "inspection", "Pre-summer AC + brake check", 650.0, None, None),
    ]:
        seed_service(token, project, user_id, "demo_vehicle_flash", currency, now,
                     days_ago=svc[0], odo=svc[1], kind=svc[2], desc=svc[3], cost=svc[4],
                     next_odo=svc[5], next_days=svc[6])

    # —— Spark: archived city runabout (history preserved) ——
    final_odos["demo_vehicle_spark"] = seed_fills(
        token, project, user_id, "demo_vehicle_spark", currency, now,
        start_odo=86200, start_days_ago=380, count=5, km_between=520,
        litres=38.0, price_per_l=2.95, stations=stations, day_step=28,
    )
    spark_trips = [
        (120, 9.5, 18, 32, 68, ["marina", "jlt", "barsha"], "auto"),
        (180, 14.2, 26, 33, 72, ["jvc", "moe", "marina"], "auto"),
        (240, 7.8, 16, 29, 58, ["dic", "media_city", "marina"], "auto"),
        (310, 11.0, 22, 30, 65, ["downtown", "business_bay", "marina"], "auto"),
        (360, 6.2, 14, 27, 52, ["marina", "jbr"], "manual"),
    ]
    for args in spark_trips:
        seed_trip(token, project, user_id, "demo_vehicle_spark", now,
                  days_ago=args[0], km=args[1], duration_min=args[2], avg=args[3],
                  max_speed=args[4], waypoint_keys=args[5], source=args[6])
    seed_service(token, project, user_id, "demo_vehicle_spark", currency, now,
                 days_ago=200, odo=87800, kind="oil", desc="Final service before archiving",
                 cost=320.0, next_odo=None, next_days=None)

    # Write garage vehicles with final odometer readings.
    for spec in vehicles:
        vid = spec["id"]
        data = {
            "userId": user_id,
            "nickname": spec["nickname"],
            "make": spec["make"],
            "model": spec["model"],
            "fuelType": spec["fuelType"],
            "currentOdometer": final_odos[vid],
            "currency": currency,
            "fuelVolumeUnit": "L",
            "fuelTankCapacity": spec["tank"],
            "icon": spec["icon"],
            "paintColor": spec["paintColor"],
            "isArchived": spec["archived"],
            "createdAt": now - timedelta(days=spec["created_days"]),
            "updatedAt": now,
        }
        if spec["archived"]:
            data["archivedAt"] = now - timedelta(days=spec["archived_days"])
        write_doc(token, project, "vehicles", vid, data)


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed Veloseete pro demo account")
    parser.add_argument("--project", default="velocity-5e576")
    parser.add_argument("--keep-auth-only", action="store_true")
    args = parser.parse_args()

    api_key = load_api_key()
    uid, token = firestore_token(api_key)
    print(f"Demo auth user: {DEMO_EMAIL} ({uid})")

    if not args.keep_auth_only:
        print("Clearing previous demo Firestore data…")
        wipe_user_data(token, args.project, uid)
        print("Seeding pro multi-vehicle garage…")
        seed_demo_data(token, args.project, uid)

    print("\nDemo account ready — full pro experience")
    print(f"  Email:     {DEMO_EMAIL}")
    print(f"  Password:  {DEMO_PASSWORD}")
    print(f"  Active:    Pearl (Camry Hybrid) · Sandstorm (Patrol) · Flash (330i)")
    print(f"  Archived:  Spark (Civic) — restore demo in Garage")
    print(f"  Fills:     27  ·  Trips: 38  ·  Service: 8")
    print(f"  Default:   Pearl selected · Fuels/Driver/Garage switcher ready")


if __name__ == "__main__":
    main()
