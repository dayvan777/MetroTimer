#!/usr/bin/env python3
"""Збирає App/Resources/kyiv_exits.json з OpenStreetMap (ODbL).

Кроки: Overpass subway_entrance по Києву → прив'язка до станцій (за назвою,
далі за близькістю <300 м) → найближча іменована вулиця (один Overpass-запит
around-полілінією, геокодинг ТУТ, не в застосунку) → проєкція на вісь
платформи (вектор між сусідніми станціями лінії) → alongM у forward-напрямку.

python3 Scripts/build_exits.py   # перезбирає датасет, мережа потрібна лише тут
"""
import json, math, urllib.request, urllib.parse, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
METRO = json.load(open(ROOT / "App/Resources/kyiv_metro.json", encoding="utf-8"))
OVERPASS = "https://overpass-api.de/api/interpreter"
BBOX = "50.30,30.30,50.55,30.75"
STREET_CLASSES = "primary|secondary|tertiary|residential|pedestrian|unclassified|living_street|trunk"

def overpass(query: str):
    import time
    data = urllib.parse.urlencode({"data": query}).encode()
    req = urllib.request.Request(OVERPASS, data=data, headers={
        "User-Agent": "MetroTimer-exits-builder/1.0 (+https://github.com/dayvan777/MetroTimer)"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.load(r)["elements"]
        except urllib.error.HTTPError as e:
            if e.code in (429, 504) and attempt < 4:
                wait = 45 * (attempt + 1)
                print(f"Overpass {e.code}, чекаю {wait}с…")
                time.sleep(wait)
            else:
                raise


def m_xy(lat, lon, lat0):
    return (lon * math.cos(math.radians(lat0)) * 111320, lat * 111320)

def dist_m(lat1, lon1, lat2, lon2):
    x1, y1 = m_xy(lat1, lon1, lat1); x2, y2 = m_xy(lat2, lon2, lat1)
    return math.hypot(x2 - x1, y2 - y1)

def pt_seg(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = 0 if l2 == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / l2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))

def norm(s):
    return s.lower().replace("’", "'").replace("ʼ", "'").strip()

stations = METRO["stations"]
by_norm = {norm(s["nameUk"]): s for s in stations}
by_id = {s["id"]: s for s in stations}

entrances = overpass(
    f'[out:json][timeout:60];node["railway"="subway_entrance"]({BBOX});out body;')
matched = {}
for e in entrances:
    st = by_norm.get(norm(e.get("tags", {}).get("name", "")))
    if not st:
        cands = [(s, dist_m(e["lat"], e["lon"], s["lat"], s["lon"])) for s in stations]
        s, d = min(cands, key=lambda x: x[1])
        st = s if d < 300 else None
    if st:
        matched.setdefault(st["id"], []).append(e)

pts = ",".join(f'{e["lat"]:.6f},{e["lon"]:.6f}' for v in matched.values() for e in v)
streets = overpass(
    f'[out:json][timeout:90];way["highway"~"^({STREET_CLASSES})$"]["name"]'
    f'(around:80,{pts});out geom tags;')

# Орієнтири біля виходів: лише класи, які впізнають миттєво. Університетські
# корпуси, лікарні й музеї навмисно пропущені — вони поруч із КОЖНИМ виходом
# у центрі та перетворюють підказку на шум.
POI_PRIORITY = ["station", "bus_station", "marketplace", "stadium"]
pois_raw = overpass(
    f'[out:json][timeout:90];('
    f'nwr["railway"="station"]["station"!="subway"]["name"](around:150,{pts});'
    f'nwr["amenity"="bus_station"]["name"](around:150,{pts});'
    f'nwr["shop"="mall"]["name"](around:150,{pts});'
    f'nwr["amenity"="marketplace"]["name"](around:120,{pts});'
    f'nwr["leisure"="stadium"]["name"](around:150,{pts});'
    f');out center tags;')
pois = []
for p in pois_raw:
    t = p.get("tags", {})
    kind = ("station" if t.get("railway") == "station" else
            t.get("amenity") or t.get("shop") or t.get("leisure"))
    name = t.get("name", "")
    lat = p.get("lat") or p.get("center", {}).get("lat")
    lon = p.get("lon") or p.get("center", {}).get("lon")
    if kind in POI_PRIORITY and name and 2 < len(name) <= 28 and lat:
        pois.append({"kind": kind, "name": name, "lat": lat, "lon": lon})

def nearest_poi(lat, lon, station_name=""):
    best = None
    sn = norm(station_name)
    for p in pois:
        # Ж/д «Святошин» біля метро «Святошин» — тавтологія, не орієнтир.
        # Точний збіг, не підрядок: «Автостанція "Видубичі"» — інший об'єкт.
        if sn and norm(p["name"]).strip('«»"') == sn:
            continue
        d = dist_m(lat, lon, p["lat"], p["lon"])
        limit = 250 if p["kind"] == "station" else 150 if p["kind"] == "bus_station" else 120
        if d > limit:
            continue
        rank = (POI_PRIORITY.index(p["kind"]), d)
        if best is None or rank < best[0]:
            best = (rank, p["name"])
    return best[1] if best else None

def nearest_street(lat, lon):
    best = None
    px, py = m_xy(lat, lon, lat)
    for w in streets:
        name = w.get("tags", {}).get("name")
        geom = w.get("geometry") or []
        if not name or len(geom) < 2:
            continue
        for a, b in zip(geom, geom[1:]):
            ax, ay = m_xy(a["lat"], a["lon"], lat)
            bx, by = m_xy(b["lat"], b["lon"], lat)
            d = pt_seg(px, py, ax, ay, bx, by)
            if best is None or d < best[0]:
                best = (d, name)
    return best[1] if best and best[0] <= 120 else None

def axis(st_id):
    for line in METRO["lines"]:
        ids = line["stationIds"]
        if st_id in ids:
            i = ids.index(st_id)
            a, b = by_id[ids[max(0, i - 1)]], by_id[ids[min(len(ids) - 1, i + 1)]]
            lat0 = by_id[st_id]["lat"]
            ax_, ay_ = m_xy(a["lat"], a["lon"], lat0)
            bx_, by_ = m_xy(b["lat"], b["lon"], lat0)
            l = math.hypot(bx_ - ax_, by_ - ay_) or 1
            return ((bx_ - ax_) / l, (by_ - ay_) / l)
    return (0, 0)

out = {}
for st_id, exits in matched.items():
    st = by_id[st_id]
    fx, fy = axis(st_id)
    sx, sy = m_xy(st["lat"], st["lon"], st["lat"])
    rows = []
    for e in exits:
        ex, ey = m_xy(e["lat"], e["lon"], st["lat"])
        t = e.get("tags", {})
        row = {
            "ref": t.get("ref"),
            "street": nearest_street(e["lat"], e["lon"]),
            "alongM": round((ex - sx) * fx + (ey - sy) * fy),
            "wheelchair": t.get("wheelchair"),
        }
        if (poi := nearest_poi(e["lat"], e["lon"], st["nameUk"])):
            row["poi"] = poi
        rows.append(row)
    rows.sort(key=lambda x: (0, int(x["ref"])) if x["ref"] and x["ref"].isdigit() else (1, 0))
    out[st_id] = rows

dest = ROOT / "App/Resources/kyiv_exits.json"
json.dump(out, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
total = sum(len(v) for v in out.values())
print(f"{dest.name}: {len(out)}/{len(stations)} станцій, {total} виходів")
