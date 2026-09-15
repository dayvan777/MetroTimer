#!/usr/bin/env python3
"""Генерирует kyiv_metro.json.

Источники данных (вересень 2026: розклад з 10.09.2026, метро працює на годину довше):
- Координаты станций: OpenStreetMap (node["station"="subway"], Київ).
- Время проезда линии конечная-конечная: Вікіпедія (инфобоксы линий).
- Времена перегонов — модель: ходовой бюджет линии (официальное время минус
  стоянки и минус T0 на разгон/торможение каждого перегона) распределяется
  между перегонами пропорционально расстояниям по прямой между станциями.
Переименования учтены: Звіринецька (экс-«Дружби народів», 2023),
Площа Українських Героїв (экс-«Площа Льва Толстого», 2023).
«Дніпро» открыта с 08.03.2024 (закрывалась в 2022–2024).
"""
import json, math, io, os

# (id, nameUk, nameEn, isClosed, isSurface)
M1 = [
    ("akademmistechko", "Академмістечко", "Akademmistechko", False, False),
    ("zhytomyrska", "Житомирська", "Zhytomyrska", False, False),
    ("sviatoshyn", "Святошин", "Sviatoshyn", False, False),
    ("nyvky", "Нивки", "Nyvky", False, False),
    ("beresteiska", "Берестейська", "Beresteiska", False, False),
    ("shuliavska", "Шулявська", "Shuliavska", False, False),
    ("politekhnichnyi-instytut", "Політехнічний інститут", "Politekhnichnyi Instytut", False, False),
    ("vokzalna", "Вокзальна", "Vokzalna", False, False),
    ("universytet", "Університет", "Universytet", False, False),
    ("teatralna", "Театральна", "Teatralna", False, False),
    ("khreshchatyk", "Хрещатик", "Khreshchatyk", False, False),
    ("arsenalna", "Арсенальна", "Arsenalna", False, False),
    ("dnipro", "Дніпро", "Dnipro", False, True),
    ("hidropark", "Гідропарк", "Hidropark", False, True),
    ("livoberezhna", "Лівобережна", "Livoberezhna", False, True),
    ("darnytsia", "Дарниця", "Darnytsia", False, True),
    ("chernihivska", "Чернігівська", "Chernihivska", False, True),
    ("lisova", "Лісова", "Lisova", False, True),
]
M2 = [
    ("heroiv-dnipra", "Героїв Дніпра", "Heroiv Dnipra", False, False),
    ("minska", "Мінська", "Minska", False, False),
    ("obolon", "Оболонь", "Obolon", False, False),
    ("pochaina", "Почайна", "Pochaina", False, False),
    ("tarasa-shevchenka", "Тараса Шевченка", "Tarasa Shevchenka", False, False),
    ("kontraktova-ploshcha", "Контрактова площа", "Kontraktova Ploshcha", False, False),
    ("poshtova-ploshcha", "Поштова площа", "Poshtova Ploshcha", False, False),
    ("maidan-nezalezhnosti", "Майдан Незалежності", "Maidan Nezalezhnosti", False, False),
    ("ploshcha-ukrainskykh-heroiv", "Площа Українських Героїв", "Ploshcha Ukrainskykh Heroiv", False, False),
    ("olimpiiska", "Олімпійська", "Olimpiiska", False, False),
    ("palats-ukraina", "Палац «Україна»", "Palats Ukraina", False, False),
    ("lybidska", "Либідська", "Lybidska", False, False),
    ("demiivska", "Деміївська", "Demiivska", False, False),
    ("holosiivska", "Голосіївська", "Holosiivska", False, False),
    ("vasylkivska", "Васильківська", "Vasylkivska", False, False),
    ("vystavkovyi-tsentr", "Виставковий центр", "Vystavkovyi Tsentr", False, False),
    ("ipodrom", "Іподром", "Ipodrom", False, False),
    ("teremky", "Теремки", "Teremky", False, False),
]
M3 = [
    ("syrets", "Сирець", "Syrets", False, False),
    ("dorohozhychi", "Дорогожичі", "Dorohozhychi", False, False),
    ("lukianivska", "Лукʼянівська", "Lukianivska", False, False),   # U+02BC — типографський апостроф, як на схемі метро,
    ("zoloti-vorota", "Золоті ворота", "Zoloti Vorota", False, False),
    ("palats-sportu", "Палац спорту", "Palats Sportu", False, False),
    ("klovska", "Кловська", "Klovska", False, False),
    ("pecherska", "Печерська", "Pecherska", False, False),
    ("zvirynetska", "Звіринецька", "Zvirynetska", False, False),
    # Видубичі — підземна станція мілкого закладення (8 м), наземний лише міст за нею.
    ("vydubychi", "Видубичі", "Vydubychi", False, False),
    ("slavutych", "Славутич", "Slavutych", False, True),
    ("osokorky", "Осокорки", "Osokorky", False, False),
    ("pozniaky", "Позняки", "Pozniaky", False, False),
    ("kharkivska", "Харківська", "Kharkivska", False, False),
    ("vyrlytsia", "Вирлиця", "Vyrlytsia", False, False),
    ("boryspilska", "Бориспільська", "Boryspilska", False, False),
    ("chervonyi-khutir", "Червоний хутір", "Chervonyi Khutir", False, False),
]

# OpenStreetMap, node["station"="subway"], выгрузка 2026-08
COORDS = {
    "akademmistechko": (50.46464, 30.35519), "zhytomyrska": (50.45608, 30.36567),
    "sviatoshyn": (50.4578, 30.39096), "nyvky": (50.45857, 30.40384),
    "beresteiska": (50.45855, 30.42237), "shuliavska": (50.45514, 30.44546),
    "politekhnichnyi-instytut": (50.45077, 30.46612), "vokzalna": (50.44166, 30.48824),
    "universytet": (50.44432, 30.50556), "teatralna": (50.44534, 30.51797),
    "khreshchatyk": (50.44736, 30.52255), "arsenalna": (50.44443, 30.5455),
    "dnipro": (50.44119, 30.55901), "hidropark": (50.44599, 30.57703),
    "livoberezhna": (50.45186, 30.59817), "darnytsia": (50.45594, 30.61284),
    "chernihivska": (50.45989, 30.63031), "lisova": (50.46451, 30.64548),
    "heroiv-dnipra": (50.52281, 30.49897), "minska": (50.51222, 30.49876),
    "obolon": (50.50136, 30.49824), "pochaina": (50.48611, 30.49829),
    "tarasa-shevchenka": (50.47328, 30.5051), "kontraktova-ploshcha": (50.46577, 30.51482),
    "poshtova-ploshcha": (50.45878, 30.52489), "maidan-nezalezhnosti": (50.45001, 30.52397),
    "ploshcha-ukrainskykh-heroiv": (50.4394, 30.51648), "olimpiiska": (50.43195, 30.51636),
    "palats-ukraina": (50.42088, 30.52098), "lybidska": (50.41288, 30.52489),
    "demiivska": (50.40474, 30.51673), "holosiivska": (50.39743, 30.50861),
    "vasylkivska": (50.39333, 30.4878), "vystavkovyi-tsentr": (50.38213, 30.47764),
    "ipodrom": (50.37687, 30.46861), "teremky": (50.36672, 30.4544),
    "syrets": (50.47646, 30.43081), "dorohozhychi": (50.47358, 30.44946),
    "lukianivska": (50.46236, 30.4818), "zoloti-vorota": (50.44856, 30.51343),
    "palats-sportu": (50.43823, 30.52106), "klovska": (50.43679, 30.53272),
    "pecherska": (50.42768, 30.53884), "zvirynetska": (50.41825, 30.54503),
    "vydubychi": (50.4017, 30.56117), "slavutych": (50.39408, 30.60477),
    "osokorky": (50.39525, 30.61619), "pozniaky": (50.39802, 30.63428),
    "kharkivska": (50.40103, 30.65197), "vyrlytsia": (50.40318, 30.66611),
    "boryspilska": (50.40316, 30.68292), "chervonyi-khutir": (50.40953, 30.69395),
}

# Основной источник времён перегонов — официальный график КП «Київський
# метрополітен» с портала открытых данных Киева (слой stopTimesUnderground:
# отправление першого/останнього поїзда з кожної станції в обох напрямках,
# точность — секунда). Значение = ход + стоянка на станции прибытия, медиана
# до 4 замеров; таблицу печатает Scripts/derive_official_times.py.
OFFICIAL_SEGMENTS = {  # ход + стоянка, сек; медиана офиц. відправлень
    ("akademmistechko", "zhytomyrska"): 145,  # n=2 [145, 145]
    ("zhytomyrska", "sviatoshyn"): 165,  # n=3 [155, 165, 170]
    ("sviatoshyn", "nyvky"): 110,  # n=4 [105, 110, 110, 120]
    ("nyvky", "beresteiska"): 108,  # n=4 [105, 105, 110, 115]
    ("beresteiska", "shuliavska"): 180,  # n=4 [175, 175, 185, 190]
    ("shuliavska", "politekhnichnyi-instytut"): 118,  # n=4 [115, 115, 120, 120]
    ("politekhnichnyi-instytut", "vokzalna"): 188,  # n=4 [180, 185, 190, 200]
    ("vokzalna", "universytet"): 118,  # n=4 [115, 115, 120, 120]
    ("universytet", "teatralna"): 112,  # n=4 [105, 110, 115, 120]
    ("teatralna", "khreshchatyk"): 115,  # n=4 [110, 115, 115, 125]
    ("khreshchatyk", "arsenalna"): 158,  # n=4 [150, 155, 160, 175]
    ("arsenalna", "dnipro"): 112,  # n=4 [110, 110, 115, 115]
    ("dnipro", "hidropark"): 168,  # n=4 [155, 165, 170, 175]
    ("hidropark", "livoberezhna"): 158,  # n=4 [155, 155, 160, 170]
    ("livoberezhna", "darnytsia"): 140,  # n=3 [140, 140, 155]
    ("darnytsia", "chernihivska"): 142,  # n=4 [135, 140, 145, 145]
    ("chernihivska", "lisova"): 128,  # n=2 [125, 130]
    ("heroiv-dnipra", "minska"): 138,  # n=2 [135, 140]
    ("minska", "obolon"): 118,  # n=4 [110, 115, 120, 125]
    ("obolon", "pochaina"): 152,  # n=4 [135, 150, 155, 160]
    ("pochaina", "tarasa-shevchenka"): 192,  # n=4 [180, 190, 195, 210]
    ("tarasa-shevchenka", "kontraktova-ploshcha"): 135,  # n=4 [120, 125, 145, 155]
    ("kontraktova-ploshcha", "poshtova-ploshcha"): 105,  # n=4 [100, 105, 105, 120]
    ("poshtova-ploshcha", "maidan-nezalezhnosti"): 135,  # n=4 [115, 125, 145, 160]  # разброс >40с
    ("maidan-nezalezhnosti", "ploshcha-ukrainskykh-heroiv"): 115,  # n=4 [110, 115, 115, 130]
    ("ploshcha-ukrainskykh-heroiv", "olimpiiska"): 112,  # n=4 [110, 110, 115, 120]
    ("olimpiiska", "palats-ukraina"): 112,  # n=4 [105, 110, 115, 120]
    ("palats-ukraina", "lybidska"): 95,  # n=3 [95, 95, 105]
    ("lybidska", "demiivska"): 110,  # n=3 [105, 110, 125]
    ("demiivska", "holosiivska"): 100,  # n=4 [100, 100, 100, 105]
    ("holosiivska", "vasylkivska"): 140,  # n=4 [135, 135, 145, 155]
    ("vasylkivska", "vystavkovyi-tsentr"): 195,  # n=3 [185, 195, 200]
    ("vystavkovyi-tsentr", "ipodrom"): 98,  # n=4 [95, 95, 100, 105]
    ("ipodrom", "teremky"): 140,  # n=2 [140, 140]
    ("syrets", "dorohozhychi"): 150,  # n=1 [150]
    ("dorohozhychi", "lukianivska"): 212,  # n=4 [200, 210, 215, 225]
    ("lukianivska", "zoloti-vorota"): 312,  # n=4 [295, 310, 315, 330]
    ("zoloti-vorota", "palats-sportu"): 125,  # n=4 [110, 115, 135, 140]
    ("palats-sportu", "klovska"): 125,  # n=4 [115, 120, 130, 135]
    ("klovska", "pecherska"): 130,  # n=4 [125, 130, 130, 135]
    ("pecherska", "zvirynetska"): 118,  # n=4 [110, 115, 120, 130]
    ("zvirynetska", "vydubychi"): 162,  # n=4 [160, 160, 165, 170]
    ("vydubychi", "slavutych"): 300,  # n=4 [285, 295, 305, 320]
    ("slavutych", "osokorky"): 100,  # n=4 [95, 95, 105, 110]
    ("osokorky", "pozniaky"): 182,  # n=4 [170, 180, 185, 195]
    ("pozniaky", "kharkivska"): 218,  # n=4 [200, 215, 220, 235]
    ("kharkivska", "vyrlytsia"): 140,  # n=4 [130, 135, 145, 150]
    ("vyrlytsia", "boryspilska"): 175,  # n=4 [155, 160, 190, 200]  # разброс >40с
    ("boryspilska", "chervonyi-khutir"): 175,  # n=1 [175]
}

# Режим роботи з тих самих офіційних шарів (виведення — Scripts/derive_official_service.py).
# Інтервали потрібні, щоб оцінити очікування поїзда на пересадці: о 8-й ранку
# це ~1.5 хв, о 22-й — до 5.5 хв.
# Інтервали руху за офіційним розкладом: (лінія, година, вихідний) →
# інтервал на початок і на кінець години, сек, прямий і зворотній напрямки.
OFFICIAL_HEADWAYS = [
    ("m1", 6, False, (435, 270), (555, 240)),
    ("m1", 7, False, (360, 180), (270, 180)),
    ("m1", 8, False, (240, 180), (210, 180)),
    ("m1", 9, False, (180, 240), (180, 240)),
    ("m1", 10, False, (210, 270), (240, 390)),
    ("m1", 11, False, (240, 390), (360, 390)),
    ("m1", 12, False, (360, 390), (390, 360)),
    ("m1", 13, False, (360, 390), (390, 360)),
    ("m1", 14, False, (390, 300), (390, 225)),
    ("m1", 15, False, (345, 225), (270, 210)),
    ("m1", 16, False, (240, 210), (225, 210)),
    ("m1", 17, False, (225, 195), (210, 195)),
    ("m1", 18, False, (210, 195), (195, 210)),
    ("m1", 19, False, (195, 300), (210, 360)),
    ("m1", 20, False, (285, 360), (300, 390)),
    ("m1", 21, False, (360, 465), (360, 465)),
    ("m1", 22, False, (390, 540), (465, 720)),
    ("m1", 23, False, (390, 540), (465, 720)),
    ("m1", 6, True, (540, 450), (600, 360)),
    ("m1", 7, True, (450, 360), (390, 360)),
    ("m1", 8, True, (390, 360), (360, 390)),
    ("m1", 9, True, (360, 390), (360, 390)),
    ("m1", 10, True, (360, 390), (390, 360)),
    ("m1", 11, True, (390, 360), (360, 390)),
    ("m1", 12, True, (360, 390), (390, 360)),
    ("m1", 13, True, (390, 360), (390, 360)),
    ("m1", 14, True, (360, 390), (360, 390)),
    ("m1", 15, True, (390, 360), (390, 360)),
    ("m1", 16, True, (390, 360), (360, 390)),
    ("m1", 17, True, (360, 390), (390, 360)),
    ("m1", 18, True, (390, 360), (390, 360)),
    ("m1", 19, True, (360, 390), (360, 390)),
    ("m1", 20, True, (360, 420), (360, 450)),
    ("m1", 21, True, (390, 450), (420, 540)),
    ("m1", 22, True, (450, 600), (480, 630)),
    ("m1", 23, True, (450, 600), (480, 630)),
    ("m2", 6, False, (510, 300), (450, 390)),
    ("m2", 7, False, (360, 210), (390, 210)),
    ("m2", 8, False, (210, 180), (240, 210)),
    ("m2", 9, False, (180, 270), (180, 240)),
    ("m2", 10, False, (240, 300), (210, 270)),
    ("m2", 11, False, (270, 390), (270, 360)),
    ("m2", 12, False, (360, 390), (300, 390)),
    ("m2", 13, False, (360, 390), (390, 360)),
    ("m2", 14, False, (390, 270), (390, 360)),
    ("m2", 15, False, (300, 270), (360, 300)),
    ("m2", 16, False, (270, 240), (300, 270)),
    ("m2", 17, False, (240, 225), (270, 240)),
    ("m2", 18, False, (225, 270), (240, 225)),
    ("m2", 19, False, (240, 390), (225, 300)),
    ("m2", 20, False, (360, 450), (300, 390)),
    ("m2", 21, False, (390, 525), (390, 450)),
    ("m2", 22, False, (480, 615), (450, 525)),
    ("m2", 23, False, (480, 615), (450, 525)),
    ("m2", 6, True, (420, 390), (450, 435)),
    ("m2", 7, True, (420, 360), (450, 390)),
    ("m2", 8, True, (360, 390), (390, 360)),
    ("m2", 9, True, (360, 390), (360, 390)),
    ("m2", 10, True, (390, 360), (360, 390)),
    ("m2", 11, True, (360, 390), (390, 360)),
    ("m2", 12, True, (390, 360), (360, 390)),
    ("m2", 13, True, (390, 360), (390, 360)),
    ("m2", 14, True, (360, 390), (360, 390)),
    ("m2", 15, True, (390, 360), (390, 360)),
    ("m2", 16, True, (360, 390), (390, 360)),
    ("m2", 17, True, (390, 360), (360, 390)),
    ("m2", 18, True, (390, 360), (390, 360)),
    ("m2", 19, True, (360, 390), (360, 390)),
    ("m2", 20, True, (390, 450), (390, 420)),
    ("m2", 21, True, (450, 615), (420, 600)),
    ("m2", 22, True, (615, 660), (600, 615)),
    ("m2", 23, True, (615, 660), (600, 615)),
    ("m3", 6, False, (450, 330), (525, 240)),
    ("m3", 7, False, (360, 210), (270, 195)),
    ("m3", 8, False, (240, 195), (195, 210)),
    ("m3", 9, False, (195, 240), (195, 300)),
    ("m3", 10, False, (210, 330), (285, 360)),
    ("m3", 11, False, (300, 360), (330, 360)),
    ("m3", 12, False, (360, 330), (360, 330)),
    ("m3", 13, False, (330, 360), (360, 330)),
    ("m3", 14, False, (360, 330), (330, 360)),
    ("m3", 15, False, (330, 360), (360, 300)),
    ("m3", 16, False, (360, 270), (300, 270)),
    ("m3", 17, False, (300, 225), (270, 210)),
    ("m3", 18, False, (240, 210), (210, 300)),
    ("m3", 19, False, (210, 330), (240, 360)),
    ("m3", 20, False, (300, 420), (360, 420)),
    ("m3", 21, False, (360, 450), (360, 600)),
    ("m3", 22, False, (420, 480), (450, 660)),
    ("m3", 23, False, (420, 480), (450, 660)),
    ("m3", 6, True, (555, 390), (660, 450)),
    ("m3", 7, True, (450, 420), (450, 420)),
    ("m3", 8, True, (450, 420), (420, 450)),
    ("m3", 9, True, (420, 450), (450, 360)),
    ("m3", 10, True, (450, 420), (450, 330)),
    ("m3", 11, True, (450, 330), (360, 330)),
    ("m3", 12, True, (330, 360), (360, 330)),
    ("m3", 13, True, (360, 330), (360, 330)),
    ("m3", 14, True, (330, 360), (360, 330)),
    ("m3", 15, True, (360, 330), (360, 330)),
    ("m3", 16, True, (360, 330), (360, 330)),
    ("m3", 17, True, (360, 330), (360, 330)),
    ("m3", 18, True, (330, 360), (330, 360)),
    ("m3", 19, True, (360, 420), (330, 450)),
    ("m3", 20, True, (360, 450), (360, 480)),
    ("m3", 21, True, (420, 480), (480, 600)),
    ("m3", 22, True, (480, 600), (480, 660)),
    ("m3", 23, True, (480, 600), (480, 660)),
]

# Перший/останній поїзд: станція → (прямий first, прямий last,
# зворотній first, зворотній last), сек від опівночі; None — кінцева.
OFFICIAL_SERVICE = {
    "akademmistechko": (21060, 84600, None, None),
    "zhytomyrska": (21205, 84745, 22380, 86770),
    "sviatoshyn": (20415, 84900, 22210, 86605),
    "nyvky": (20525, 85005, 22090, 86495),
    "beresteiska": (20630, 85110, 21975, 86385),
    "shuliavska": (20820, 85285, 21790, 86210),
    "politekhnichnyi-instytut": (20940, 85400, 21670, 86095),
    "vokzalna": (21130, 85580, 21470, 85910),
    "universytet": (21250, 85695, 21350, 85795),
    "teatralna": (21370, 85810, 21240, 85690),
    "khreshchatyk": (21495, 85925, 21125, 85580),
    "arsenalna": (21650, 86075, 20950, 85420),
    "dnipro": (21765, 86185, 20835, 85310),
    "hidropark": (21940, 86355, 20670, 85155),
    "livoberezhna": (22110, 86510, 20510, 85000),
    "darnytsia": (21060, 86650, 20355, 84860),
    "chernihivska": (21205, 86795, 20215, 84725),
    "lisova": (None, None, 20085, 84600),
    "heroiv-dnipra": (19800, 84600, None, None),
    "minska": (19940, 84735, 21745, 86635),
    "obolon": (20065, 84855, 21630, 86525),
    "pochaina": (20225, 85005, 21475, 86390),
    "tarasa-shevchenka": (20415, 85185, 21265, 86195),
    "kontraktova-ploshcha": (20540, 85305, 21110, 86050),
    "poshtova-ploshcha": (20645, 85405, 20990, 85945),
    "maidan-nezalezhnosti": (20805, 85550, 20865, 85830),
    "ploshcha-ukrainskykh-heroiv": (20920, 85660, 20735, 85715),
    "olimpiiska": (21035, 85770, 20615, 85600),
    "palats-ukraina": (21145, 85875, 20495, 85490),
    "lybidska": (21250, 85970, 21420, 85395),
    "demiivska": (21360, 86075, 21720, 85270),
    "holosiivska": (21460, 86175, 21615, 85170),
    "vasylkivska": (21615, 86320, 21480, 85035),
    "vystavkovyi-tsentr": (21810, 86505, 21690, 84835),
    "ipodrom": (21915, 86600, 21590, 84740),
    "teremky": (None, None, 21450, 84600),
    "syrets": (21600, 84600, None, None),
    "dorohozhychi": (20385, 84750, 22155, 86660),
    "lukianivska": (20610, 84965, 21945, 86460),
    "zoloti-vorota": (20940, 85275, 21630, 86165),
    "palats-sportu": (21080, 85410, 21515, 86055),
    "klovska": (21200, 85525, 21380, 85925),
    "pecherska": (21335, 85655, 21250, 85800),
    "zvirynetska": (21465, 85775, 21135, 85690),
    "vydubychi": (21630, 85935, 20965, 85530),
    "slavutych": (21925, 86220, 20645, 85225),
    "osokorky": (22035, 86325, 20550, 85130),
    "pozniaky": (22230, 86510, 20370, 84960),
    "kharkivska": (22465, 86730, 20155, 84760),
    "vyrlytsia": (22615, 86875, 20020, 84630),
    "boryspilska": (22815, 87065, 19860, 84475),
    "chervonyi-khutir": (None, None, 21420, 84300),
}

# Запасная модель для перегонов без официальных данных.
# Время проезда линии конечная-конечная, мин.
# m1/m3 — Вікіпедія; m2 — полевой замер 12.08.2026 (Героїв Дніпра→Майдан:
# план по вики-времени 14:04, факт ~16:04 → официальные 34.0 занижены на ~14%).
OFFICIAL = {"m1": 38.5, "m2": 38.5, "m3": 39.0}
DWELL = 25   # стоянка, сек
T0 = 20      # разгон + торможение на перегон, сек

# Пересадочные узлы: walkSeconds = ТОЛЬКО переход пешком, в темпе спешащего
# пассажира. Ожидание поезда сюда не входит — см. MetroRepository.
#
# Замер важнее догадки: 240 с на Хрещатик↔Майдан были вписаны «на глаз» и
# оказались вдвое больше реальности (полевой замер 17.08.2026 — 2 хвилини
# пешком). Два других узла ещё НЕ ЗАМЕРЯНЫ: значения ниже — оценка, их надо
# проверить в поездке и поправить так же.
# Пары двунаправленные; каждая пара линий в Киеве связана ровно одним узлом.
TRANSFERS = [
    ("teatralna", "zoloti-vorota", 150),                   # M1 ↔ M3 — не замерян
    ("khreshchatyk", "maidan-nezalezhnosti", 120),          # M1 ↔ M2 — замер 17.08.2026
    ("ploshcha-ukrainskykh-heroiv", "palats-sportu", 150),  # M2 ↔ M3 — не замерян
]

# Ділянки без руху (ремонт, пошкодження). Пари двонаправлені; маршрут через них
# застосунок не будує. Станом на серпень 2026 рух відновлено скрізь.
SUSPENDED = set()

# Робота під час повітряних тривог — правила КМДА з 10.09.2026 (рівні тривог
# запроваджено 06.09.2026): червона гілка при тривозі БУДЬ-ЯКОГО рівня курсує
# лише Академмістечко–Арсенальна, лівий берег стоїть; зелена при червоному
# рівні розривається на Сирець–Видубичі та Славутич–Червоний хутір, при жовтому
# їде через Південний міст без обмежень. Синя — під землею повністю.
ALERT_STOPS = {
    ("arsenalna", "dnipro"): "any", ("dnipro", "hidropark"): "any",
    ("hidropark", "livoberezhna"): "any", ("livoberezhna", "darnytsia"): "any",
    ("darnytsia", "chernihivska"): "any", ("chernihivska", "lisova"): "any",
    ("vydubychi", "slavutych"): "red",
}

LINES = [
    ("m1", "Святошинсько-Броварська", "#ED1C24", M1),
    ("m2", "Оболонсько-Теремківська", "#0072BC", M2),
    ("m3", "Сирецько-Печерська", "#00A651", M3),
]


def haversine(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = math.sin((lat2 - lat1) / 2) ** 2 + \
        math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371000 * 2 * math.asin(math.sqrt(h))


def segment_times(line_id, sts):
    ids = [s[0] for s in sts]
    straight = [haversine(COORDS[a], COORDS[b]) for a, b in zip(ids, ids[1:])]
    # Стоянки — только на промежуточных открытых станциях (как в TripPlanner.fill).
    dwell_stops = sum(1 for s in sts[1:-1] if not s[3])
    run_budget = OFFICIAL[line_id] * 60 - DWELL * dwell_stops - T0 * len(straight)
    total = sum(straight)
    model = [round(T0 + s / total * run_budget) for s in straight]
    # Официальный график: ход = (отправление→отправление) − стоянка.
    times = []
    for (a, b), fallback in zip(zip(ids, ids[1:]), model):
        official = OFFICIAL_SEGMENTS.get((a, b))
        times.append(max(30, official - DWELL) if official else fallback)
    return times, dwell_stops


def main():
    lines, stations, segments = [], [], []
    for lid, name, color, sts in LINES:
        ids = [s[0] for s in sts]
        lines.append({"id": lid, "nameUk": name, "colorHex": color, "stationIds": ids})
        for sid, uk, en, closed, surface in sts:
            lat, lon = COORDS[sid]
            stations.append({"id": sid, "nameUk": uk, "nameEn": en, "isClosed": closed,
                             "isSurface": surface, "lat": lat, "lon": lon})
        times, dwell_stops = segment_times(lid, sts)
        for (a, b), t in zip(zip(ids, ids[1:]), times):
            suspended = (a, b) in SUSPENDED or (b, a) in SUSPENDED
            segment = {"fromId": a, "toId": b, "travelSeconds": t, "dwellSeconds": DWELL,
                       "isSuspended": suspended}
            alert_stop = ALERT_STOPS.get((a, b)) or ALERT_STOPS.get((b, a))
            if alert_stop:
                segment["alertStop"] = alert_stop
            segments.append(segment)
        total = sum(times) + DWELL * dwell_stops
        print(f"{lid}: {len(times)} segments {min(times)}-{max(times)}s, "
              f"end-to-end {total/60:.1f} min")

    # Переходы: в transfers — для маршрутизации, в segments — чтобы timing() их знал.
    transfers = [{"fromId": a, "toId": b, "walkSeconds": w} for a, b, w in TRANSFERS]
    for a, b, w in TRANSFERS:
        segments.append({"fromId": a, "toId": b, "travelSeconds": w, "dwellSeconds": 0,
                         "isSuspended": False})

    # Интервалы движения по часам: ожидание поезда на пересадке и «як часто їздять».
    headways = [{"lineId": lid, "hour": hour, "isHoliday": holiday,
                 "forwardStart": fwd[0], "forwardEnd": fwd[1],
                 "backwardStart": back[0], "backwardEnd": back[1]}
                for lid, hour, holiday, fwd, back in OFFICIAL_HEADWAYS]

    # Перший/останній поїзд: секунды от полуночи, None у конечной в её сторону.
    service = [{"stationId": sid, "forwardFirst": f0, "forwardLast": f1,
                "backwardFirst": b0, "backwardLast": b1}
               for sid, (f0, f1, b0, b1) in OFFICIAL_SERVICE.items()]

    data = {"lines": lines, "stations": stations, "segments": segments,
            "transfers": transfers, "headways": headways, "serviceHours": service}
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "App", "Resources", "kyiv_metro.json")
    with io.open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"stations={len(stations)} segments={len(segments)} "
          f"headways={len(headways)} service={len(service)} -> {out}")


if __name__ == "__main__":
    main()
