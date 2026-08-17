#!/usr/bin/env python3
"""Сливает экспорты калибровки с нескольких устройств в один calibration.json.

Использование:
    python3 Scripts/merge_calibration.py export1/calibration.json export2/calibration.json ...

Записи усредняются с весом по числу замеров (travel и dwell независимо).
Результат: merged_calibration.json рядом со скриптом + сводная таблица в stdout.
Полученный файл можно положить в Documents устройства (через Finder → iPhone →
Files → MetroTimer) — приложение подхватит его как свою калибровку.
"""
import json
import sys
from pathlib import Path


def merge(paths):
    merged = {}
    for path in paths:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        for key, record in data.items():
            target = merged.setdefault(key, {
                "travelSeconds": None, "travelSamples": 0,
                "dwellSeconds": None, "dwellSamples": 0,
            })
            for value_key, samples_key in (("travelSeconds", "travelSamples"),
                                           ("dwellSeconds", "dwellSamples")):
                value, samples = record.get(value_key), record.get(samples_key, 0)
                if value is None or samples <= 0:
                    continue
                old_value = target[value_key] or 0
                old_samples = target[samples_key]
                total = old_samples + samples
                target[value_key] = (old_value * old_samples + value * samples) / total
                target[samples_key] = total
    return merged


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    merged = merge(sys.argv[1:])
    out = Path(__file__).parent / "merged_calibration.json"
    out.write_text(json.dumps(merged, ensure_ascii=False, indent=2, sort_keys=True),
                   encoding="utf-8")
    print(f"{'перегон':44} {'хід, с':>8} {'замірів':>8} {'стоянка, с':>11} {'замірів':>8}")
    for key in sorted(merged):
        record = merged[key]
        travel = f"{record['travelSeconds']:.0f}" if record["travelSeconds"] else "—"
        dwell = f"{record['dwellSeconds']:.0f}" if record["dwellSeconds"] else "—"
        print(f"{key:44} {travel:>8} {record['travelSamples']:>8} "
              f"{dwell:>11} {record['dwellSamples']:>8}")
    print(f"\n{len(merged)} перегонов -> {out}")


if __name__ == "__main__":
    main()
