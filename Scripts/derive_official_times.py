#!/usr/bin/env python3
"""Выводит поперегонные времена метро из официального слоя открытых данных Киева
«Розклад руху…» → stopTimesUnderground (время отправления першого/останнього
поїзда з кожної станції в обох напрямках, з точністю до секунди).

Разность отправлений соседних станций = ход перегона + стоянка на станции
прибытия. На перегон приходится до 4 замеров (перший/останній × прямий/зворотній);
берём медиану правдоподобных (60…420 с), выбросы от поездов из депо
(старт с промежуточной станции даёт отрицательную или огромную разность) —
отбрасываем. Результат печатается как литерал OFFICIAL_SEGMENTS для
gen_metro_json.py (генератор остаётся офлайн-самодостаточным).

Источник: https://data.kyivcity.gov.ua/dataset/rozklad-rukhu-miskoho-elektrychnoho-ta-avtomobilnoho-transportu-dep-transport
Слой: https://gisserver-stage.kyivcity.gov.ua/mayno/rest/services/KYIV_API/transport_public/MapServer/13/query?where=1%3D1&outFields=*&f=pjson
Использование: derive_official_times.py stoptimes.json
"""
import json
import statistics
import sys
from collections import defaultdict

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from gen_metro_json import M1, M2, M3  # noqa: E402  (списки станций генератора)

LINE_BY_NAME = {
    "Святошинсько-Броварська": M1,
    "Оболонсько-Теремківська": M2,
    "Сирецько-Печерська": M3,
}
PLAUSIBLE = range(60, 421)


def sec(t):
    if not t:
        return None
    parts = [int(x) for x in t.split(":")]
    while len(parts) < 3:
        parts.append(0)
    return parts[0] * 3600 + parts[1] * 60 + parts[2]


def norm(name):
    return (name.replace("ʼ", "'").replace("’", "'").replace("«", "").replace("»", "")
            .strip().lower())


def main(path):
    rows = [f["attributes"] for f in json.load(open(path))["features"]]
    groups = defaultdict(list)
    for r in rows:
        groups[(r["line"], r["napryamok"])].append(r)

    samples = defaultdict(list)          # (fromId, toId) в порядке линии → [Δ, ...]
    for (line_name, direction), lst in groups.items():
        lst.sort(key=lambda r: r["objectid"])
        sts = LINE_BY_NAME[line_name]
        id_by_norm = {norm(s[1]): s[0] for s in sts}
        for a, b in zip(lst, lst[1:]):
            ia, ib = id_by_norm[norm(a["name"])], id_by_norm[norm(b["name"])]
            for kind in ("first_trn", "last_trn"):
                # v2 (с секундами) приоритетнее v1 (минуты) для того же поезда.
                ta = sec(a.get(kind + "2")) or sec(a.get(kind + "1"))
                tb = sec(b.get(kind + "2")) or sec(b.get(kind + "1"))
                if ta is None or tb is None:
                    continue
                delta = tb - ta
                if direction == "Зворотній":
                    delta = -delta       # список в прямом порядке, поезд идёт назад
                if delta in PLAUSIBLE:
                    samples[(ia, ib)].append(delta)

    print("OFFICIAL_SEGMENTS = {  # ход + стоянка, сек; медиана офиц. відправлень")
    for sts in (M1, M2, M3):
        ids = [s[0] for s in sts]
        for a, b in zip(ids, ids[1:]):
            vals = samples.get((a, b), [])
            if not vals:
                print(f"    # {a} -> {b}: НЕТ ДАННЫХ")
                continue
            med = round(statistics.median(vals))
            spread = max(vals) - min(vals)
            flag = "  # разброс >40с" if spread > 40 else ""
            print(f'    ("{a}", "{b}"): {med},  # n={len(vals)} {sorted(vals)}{flag}')
    print("}")


if __name__ == "__main__":
    main(sys.argv[1])
