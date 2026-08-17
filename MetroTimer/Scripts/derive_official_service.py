#!/usr/bin/env python3
"""Выводит режим работы метро из официальных слоёв открытых данных Киева:

  1. Интервалы движения по часам (слой MapServer/14 «Інтервали руху»):
     на каждую линию, час, тип дня и направление — интервал на начало и на конец
     часа (в источнике это диапазон «7:30-5:30», т.е. интервал плавно меняется
     внутри часа). Нужны, чтобы оценить ожидание поезда на пересадке: вечером
     оно втрое больше, чем в час пик.

  2. Перший/останній поїзд по станциям (слой MapServer/13 «stopTimesUnderground»):
     время отправления в каждом направлении, с точностью до секунды.

Результат печатается как литералы OFFICIAL_HEADWAYS / OFFICIAL_SERVICE для
gen_metro_json.py (генератор остаётся офлайн-самодостаточным).

Источник: https://data.kyivcity.gov.ua/dataset/rozklad-rukhu-miskoho-elektrychnoho-ta-avtomobilnoho-transportu-dep-transport
Скачивание (сервер отдаёт JSON только с User-Agent браузера):
  BASE=https://gisserver-stage.kyivcity.gov.ua/mayno/rest/services/KYIV_API/transport_public/MapServer
  curl -A "Mozilla/5.0" "$BASE/14/query?where=1%3D1&outFields=*&f=json" -o intervals.json
  curl -A "Mozilla/5.0" "$BASE/13/query?where=1%3D1&outFields=*&f=json" -o stoptimes.json
Использование: derive_official_service.py intervals.json stoptimes.json
"""
import json
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from gen_metro_json import M1, M2, M3  # noqa: E402  (списки станций генератора)

LINE_ID_BY_NAME = {
    "Святошинсько-Броварська": "m1",
    "Оболонсько-Теремківська": "m2",
    "Сирецько-Печерська": "m3",
}
# Порядок списков генератора совпадает с «Прямим» напрямком источника
# (первая станция списка = та, откуда идёт первый поезд прямого направления).
STATIONS = {"m1": M1, "m2": M2, "m3": M3}


def mmss(value):
    """«7:30» → 450 сек. Пустое значение → None."""
    if not value:
        return None
    parts = [int(x) for x in value.strip().split(":")]
    return parts[0] * 60 + (parts[1] if len(parts) > 1 else 0)


def span(value):
    """«7:30-5:30» → (450, 330); «3:00» → (180, 180)."""
    if not value:
        return None
    halves = value.split("-")
    start = mmss(halves[0])
    end = mmss(halves[1]) if len(halves) > 1 else start
    return (start, end) if start and end else None


def hhmmss(value):
    """«22:30:15» или «22:30» → секунды от полуночи. Пустое → None."""
    if not value:
        return None
    parts = [int(x) for x in value.strip().split(":")]
    while len(parts) < 3:
        parts.append(0)
    return parts[0] * 3600 + parts[1] * 60 + parts[2]


def norm(name):
    return (name.replace("ʼ", "'").replace("’", "'").replace("«", "").replace("»", "")
            .strip().lower())


def headways(path):
    rows = [f["attributes"] for f in json.load(open(path))["features"]]
    out = []
    for r in rows:
        line_id = LINE_ID_BY_NAME.get(r["line"])
        hour = int(r["timeperiod"].split(":")[0])
        for holiday, (fwd, back) in ((False, ("st_weekday", "rv_weekday")),
                                     (True, ("st_holiday", "rv_holiday"))):
            forward, backward = span(r[fwd]), span(r[back])
            if not line_id or not forward or not backward:
                continue
            out.append((line_id, hour, holiday, forward, backward))
    out.sort(key=lambda x: (x[0], x[2], x[1]))

    print("# Інтервали руху за офіційним розкладом: (лінія, година, вихідний) →")
    print("# інтервал на початок і на кінець години, сек, прямий і зворотній напрямки.")
    print("OFFICIAL_HEADWAYS = [")
    for line_id, hour, holiday, forward, backward in out:
        print(f'    ("{line_id}", {hour}, {holiday}, {forward}, {backward}),')
    print("]")
    return out


def service(path):
    rows = [f["attributes"] for f in json.load(open(path))["features"]]
    # (station_id) → {"fwd": (first, last), "back": (first, last)}
    by_station = {}
    id_by_norm = {}
    for sts in STATIONS.values():
        for s in sts:
            id_by_norm[norm(s[1])] = s[0]

    for r in rows:
        sid = id_by_norm.get(norm(r["name"]))
        if not sid:
            print(f"# НЕВІДОМА СТАНЦІЯ: {r['name']}", file=sys.stderr)
            continue
        key = "fwd" if r["napryamok"] == "Прямий" else "back"
        first = hhmmss(r.get("first_trn2")) or hhmmss(r.get("first_trn1"))
        last = hhmmss(r.get("last_trn2")) or hhmmss(r.get("last_trn1"))
        if first is None and last is None:
            continue                      # конечная: в эту сторону поезд не отправляется
        by_station.setdefault(sid, {})[key] = (first, last)

    print()
    print("# Перший/останній поїзд: станція → (прямий first, прямий last,")
    print("# зворотній first, зворотній last), сек від опівночі; None — кінцева.")
    print("OFFICIAL_SERVICE = {")
    for sts in (M1, M2, M3):
        for s in sts:
            sid = s[0]
            entry = by_station.get(sid)
            if not entry:
                print(f'    # "{sid}": НЕТ ДАННЫХ')
                continue
            fwd = entry.get("fwd", (None, None))
            back = entry.get("back", (None, None))
            print(f'    "{sid}": ({fwd[0]}, {fwd[1]}, {back[0]}, {back[1]}),')
    print("}")
    return by_station


def main(intervals_path, stoptimes_path):
    rows = headways(intervals_path)
    stations = service(stoptimes_path)
    print(f"\n# інтервалів: {len(rows)}, станцій з розкладом: {len(stations)}",
          file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
