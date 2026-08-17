#!/usr/bin/env python3
"""Генерирует kyiv_metro.json.

Источники данных (август 2026):
- Координаты станций: OpenStreetMap (node["station"="subway"], Київ).
- Время проезда линии конечная-конечная: Вікіпедія (инфобоксы линий).
- Времена перегонов — модель: ходовой бюджет линии (официальное время минус
  стоянки и минус T0 на разгон/торможение каждого перегона) распределяется
  между перегонами пропорционально расстояниям по прямой между станциями.
Переименования учтены: Звіринецька (экс-«Дружби народів», 2023),
Площа Українських Героїв (экс-«Площа Льва Толстого», 2023).
«Дніпро» открыта с 08.03.2024 (закрывалась в 2022–2024).
"""
import json, math, io

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
    ("vydubychi", "Видубичі", "Vydubychi", False, True),
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
    ("m1", 6, False, (540, 240), (495, 210)),
    ("m1", 7, False, (300, 180), (240, 165)),
    ("m1", 8, False, (210, 165), (180, 165)),
    ("m1", 9, False, (165, 225), (165, 300)),
    ("m1", 10, False, (210, 330), (240, 330)),
    ("m1", 11, False, (300, 330), (330, 300)),
    ("m1", 12, False, (330, 300), (330, 300)),
    ("m1", 13, False, (330, 300), (330, 300)),
    ("m1", 14, False, (330, 255), (330, 255)),
    ("m1", 15, False, (330, 225), (255, 225)),
    ("m1", 16, False, (255, 210), (225, 180)),
    ("m1", 17, False, (210, 180), (210, 180)),
    ("m1", 18, False, (180, 180), (180, 240)),
    ("m1", 19, False, (180, 330), (180, 360)),
    ("m1", 20, False, (300, 390), (360, 390)),
    ("m1", 21, False, (360, 420), (360, 450)),
    ("m1", 22, False, (420, 540), (405, 600)),
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
    ("m2", 6, False, (390, 210), (450, 300)),
    ("m2", 7, False, (270, 180), (390, 210)),
    ("m2", 8, False, (180, 165), (210, 180)),
    ("m2", 9, False, (165, 270), (165, 240)),
    ("m2", 10, False, (240, 300), (210, 300)),
    ("m2", 11, False, (270, 390), (270, 360)),
    ("m2", 12, False, (360, 390), (300, 390)),
    ("m2", 13, False, (360, 390), (390, 360)),
    ("m2", 14, False, (390, 270), (390, 360)),
    ("m2", 15, False, (300, 240), (360, 270)),
    ("m2", 16, False, (240, 210), (300, 225)),
    ("m2", 17, False, (225, 180), (240, 210)),
    ("m2", 18, False, (180, 270), (225, 180)),
    ("m2", 19, False, (180, 390), (180, 300)),
    ("m2", 20, False, (300, 450), (270, 390)),
    ("m2", 21, False, (300, 510), (390, 450)),
    ("m2", 22, False, (510, 660), (450, 615)),
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
    ("m3", 6, False, (450, 330), (525, 225)),
    ("m3", 7, False, (360, 210), (270, 180)),
    ("m3", 8, False, (225, 165), (165, 210)),
    ("m3", 9, False, (165, 240), (180, 285)),
    ("m3", 10, False, (210, 360), (270, 360)),
    ("m3", 11, False, (270, 360), (330, 360)),
    ("m3", 12, False, (360, 330), (360, 330)),
    ("m3", 13, False, (330, 360), (360, 330)),
    ("m3", 14, False, (360, 330), (330, 360)),
    ("m3", 15, False, (330, 360), (360, 270)),
    ("m3", 16, False, (360, 240), (270, 225)),
    ("m3", 17, False, (270, 180), (225, 180)),
    ("m3", 18, False, (180, 240), (195, 300)),
    ("m3", 19, False, (225, 330), (255, 360)),
    ("m3", 20, False, (300, 420), (360, 450)),
    ("m3", 21, False, (360, 450), (450, 540)),
    ("m3", 22, False, (450, 540), (450, 660)),
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
]

# Перший/останній поїзд: станція → (прямий first, прямий last,
# зворотній first, зворотній last), сек від опівночі; None — кінцева.
OFFICIAL_SERVICE = {
    "akademmistechko": (21060, 81000, None, None),
    "zhytomyrska": (21205, 81145, 22380, 83170),
    "sviatoshyn": (20415, 81300, 22210, 83005),
    "nyvky": (20525, 81405, 22090, 82895),
    "beresteiska": (20630, 81510, 21975, 82785),
    "shuliavska": (20820, 81685, 21790, 82610),
    "politekhnichnyi-instytut": (20940, 81800, 21670, 82495),
    "vokzalna": (21130, 81980, 21470, 82310),
    "universytet": (21250, 82095, 21350, 82195),
    "teatralna": (21370, 82210, 21240, 82090),
    "khreshchatyk": (21495, 82325, 21125, 81980),
    "arsenalna": (21650, 82475, 20950, 81820),
    "dnipro": (21765, 82585, 20835, 81710),
    "hidropark": (21940, 82755, 20670, 81555),
    "livoberezhna": (22110, 82910, 20510, 81400),
    "darnytsia": (21060, 83050, 20355, 81260),
    "chernihivska": (21205, 83195, 20215, 81125),
    "lisova": (None, None, 20085, 81000),
    "heroiv-dnipra": (19800, 81000, None, None),
    "minska": (19940, 81135, 21745, 83035),
    "obolon": (20065, 81255, 21630, 82925),
    "pochaina": (20225, 81405, 21475, 82790),
    "tarasa-shevchenka": (20415, 81585, 21265, 82595),
    "kontraktova-ploshcha": (20540, 81705, 21110, 82450),
    "poshtova-ploshcha": (20645, 81805, 20990, 82345),
    "maidan-nezalezhnosti": (20805, 81950, 20865, 82230),
    "ploshcha-ukrainskykh-heroiv": (20920, 82060, 20735, 82115),
    "olimpiiska": (21030, 82170, 20615, 82000),
    "palats-ukraina": (21145, 82275, 20495, 81890),
    "lybidska": (21250, 82370, 21420, 81795),
    "demiivska": (21360, 82475, 21720, 81670),
    "holosiivska": (21460, 82575, 21615, 81570),
    "vasylkivska": (21615, 82720, 21480, 81435),
    "vystavkovyi-tsentr": (21810, 82905, 21690, 81235),
    "ipodrom": (21915, 83000, 21590, 81140),
    "teremky": (None, None, 21450, 81000),
    "syrets": (21600, 81000, None, None),
    "dorohozhychi": (20385, 81150, 22155, 83060),
    "lukianivska": (20610, 81365, 21945, 82860),
    "zoloti-vorota": (20940, 81675, 21630, 82565),
    "palats-sportu": (21080, 81810, 21515, 82455),
    "klovska": (21200, 81925, 21380, 82325),
    "pecherska": (21335, 82055, 21250, 82200),
    "zvirynetska": (21465, 82175, 21135, 82090),
    "vydubychi": (21630, 82335, 20965, 81930),
    "slavutych": (21925, 82620, 20645, 81625),
    "osokorky": (22035, 82725, 20550, 81530),
    "pozniaky": (22230, 82910, 20370, 81360),
    "kharkivska": (22465, 83130, 20155, 81160),
    "vyrlytsia": (22615, 83275, 20020, 81030),
    "boryspilska": (22815, 83465, 19860, 80875),
    "chervonyi-khutir": (None, None, 21420, 80700),
}

# Запасная модель для перегонов без официальных данных.
# Время проезда линии конечная-конечная, мин.
# m1/m3 — Вікіпедія; m2 — полевой замер 12.08.2026 (Героїв Дніпра→Майдан:
# план по вики-времени 14:04, факт ~16:04 → официальные 34.0 занижены на ~14%).
OFFICIAL = {"m1": 38.5, "m2": 38.5, "m3": 39.0}
DWELL = 25   # стоянка, сек
T0 = 20      # разгон + торможение на перегон, сек

# Пересадочные узлы: walkSeconds = ТОЛЬКО переход пешком. Ожидание поезда
# больше сюда не входит — оно считается по интервалу движения на момент выхода
# на платформу (OFFICIAL_HEADWAYS): вечером ждать втрое дольше, чем в час пик.
# Пары двунаправленные; каждая пара линий в Киеве связана ровно одним узлом.
TRANSFERS = [
    ("teatralna", "zoloti-vorota", 180),                   # M1 ↔ M3
    ("khreshchatyk", "maidan-nezalezhnosti", 240),          # M1 ↔ M2 (длинный переход)
    ("ploshcha-ukrainskykh-heroiv", "palats-sportu", 180),  # M2 ↔ M3
]

# Ділянки без руху (ремонт, пошкодження). Пари двонаправлені; маршрут через них
# застосунок не будує. Станом на серпень 2026 рух відновлено скрізь.
SUSPENDED = set()

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
            segments.append({"fromId": a, "toId": b, "travelSeconds": t, "dwellSeconds": DWELL,
                             "isSuspended": suspended})
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
    out = "/Users/macbook/Downloads/влад/MetroTimer/App/Resources/kyiv_metro.json"
    with io.open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"stations={len(stations)} segments={len(segments)} "
          f"headways={len(headways)} service={len(service)} -> {out}")


if __name__ == "__main__":
    main()
