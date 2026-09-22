# App Store — metadata (English)

Second App Store localization. The app itself switches language automatically
(`Shared/Localization.swift`), so this listing must exist alongside the
Ukrainian one — see `metadata_uk.md` for the primary listing and the
App Store Connect checklist, which applies to both.

## Name (up to 30 chars)
Metro Timer: Kyiv

## Subtitle (up to 30 chars)
Never miss your stop

## Promotional text (up to 170 chars)
An alarm one stop before yours, a Dynamic Island countdown that keeps moving on its own, and “I got off” on the Lock Screen. Works with no internet.

## Description
Dozing off, reading or listening to music on the metro? Metro Timer reminds you of your stop.

How it works: pick your stations and tap “Start” when the train pulls out. From then on the countdown runs by itself: the Lock Screen and the Dynamic Island show how long is left to your station, and a notification comes one stop before yours. Tapped too late? Tap the station where the train is now and the countdown catches up.

AN ALARM ONE STOP EARLY
If you tend to fall asleep on the way, turn on the alarm on the trip screen. On iOS 26 and later it rings even in silent mode until you turn it off. On older iOS the alert repeats three times.

DYNAMIC ISLAND AND LOCK SCREEN
The ring, the countdown and the station bar keep moving on their own, even with the app closed: Dynamic Island on iPhone 14 Pro and later, the Lock Screen on any iPhone with iOS 16.1+. Arrived? “I got off” right on the Lock Screen (iOS 17+).

WORKS OFFLINE
There is no signal underground and none is needed: the app works out the time to every station from the official Kyiv Metro timetable. No servers, no ads, no analytics. Only the air-raid alert banner needs the internet, and it stays off until you turn it on.

SHARE YOUR ARRIVAL TIME
One tap for whoever is meeting you: “I’ll be at Zoloti Vorota around 8:31”.

LINE CHANGES, DIRECTION AND EXITS
Routes between lines are built automatically, with the direction of travel as shown on the platform signs and a separate alert where to change. Before you board you see which end of the train is nearer to which exit, and before you get off the app shows the station’s exits.

MY YEAR ON THE METRO
Trips, hours underground, stations passed and your favourite station. The story card is calculated only on your phone.

QUICK START
Station search, including old names (Petrivka, Lva Tolstoho), pinned routes and recent trips. Say “Last route in Metro Timer” to Siri and the app opens with the stations already filled in.

MORE PRECISE ABOVE GROUND
On above-ground sections, while the app is open, it checks its estimate against GPS. Underground you make the correction: tap a station or use ±1.

YOUR DATA STAYS WITH YOU
The app collects and transmits nothing. The trip journal and statistics live only on your phone.

The estimate is approximate, so check the station signs. All 52 stations of the three Kyiv metro lines. Made in Ukraine.

Unofficial app; not affiliated with Kyiv Metro or the Kyiv City Administration. Data: Kyiv Open Data Portal; station coordinates © OpenStreetMap contributors (ODbL).

## Keywords (up to 100 chars)
kiev,subway,underground,station,alarm,exit,map,ukraine,train,wake,transit,offline,commute

Why (review 22.09.2026): the Ukrainian storefront also indexes the **English (U.K.)** listing,
so this text must go into an **English (U.K.)** localization in App Store Connect, not only
English (U.S.). Words already in the name and subtitle (metro, timer, kyiv, stop) are indexed
anyway and are not repeated here. Keywords can change only together with a new version.

## Categories
- Primary: Navigation
- Secondary: Travel

## Age rating
4+

## What's new (version 1.4)

A big update built from your feedback.

• Tapped “Start” too late? Tap the station where the train is and the countdown catches up.
• An alarm one stop before yours: on iOS 26 it rings even in silent mode.
• A new Dynamic Island: the ring and the station bar keep moving on their own, nothing freezes.
• “I got off” right on the Lock Screen.
• “Share arrival time” for whoever is meeting you.
• Direction of travel and which end of the train is nearer to the exits, before you board.
• Search by old station names: Petrivka, Lva Tolstoho, Druzhby Narodiv.
• “My year on the metro”: your stats and a story card.
• The arrival alert now asks you to check the station sign.

Thank you for every review.

## What’s new (version 1.3.2)

A small but visible fix: on iOS 26 the system search field moved to the bottom of the screen and stuck to the “Go” button. Search is now a compact button: it opens with one tap and covers nothing.

Thanks to the observant passengers for the screenshots!

## What’s new (version 1.3.1)

A reliability update: we fixed everything that could make the warning come too late.

• Central transfer stations. If your stop is on the other line of the same transfer hub (say, riding the red line to Zoloti Vorota or Maidan Nezalezhnosti), "Yours is next" used to arrive when the doors were already open. Now it comes one stop before you leave the train, and the counter counts train stops only.
• Routes that start at such a station: the countdown begins where your train actually departs and no longer lags by the walking time.
• "+1 stop" right after a transfer no longer adds extra minutes.
• Clock-change days: first and last trains are shown at the correct time.
• Surface sections: a train held during an air-raid alert no longer teaches the app to count slower.
• Pinned routes and the trip journal are no longer lost if you tap a button on the locked screen.

Thank you for riding with us and for telling us where the count is off.

## What’s new (version 1.3)

The metro runs an hour longer — so does the app.

Since September 10 the last trains leave at 23:30, not 22:30. Timetable, headways and the first/last-train warnings are updated from Kyiv's open data, including trains that arrive after midnight.

Alerts are now yellow or red — and the app explains what that means for your route: during any alert the red line runs only as far as Arsenalna; under a yellow alert the green line crosses the Southern Bridge, under a red one it does not.

From your feedback:
• Vydubychi is no longer marked above ground — the station is underground.
• The map no longer jumps when you pinch to zoom.
• Ukrainian stays Ukrainian even when English is your phone's second language.
• The Lock Screen shows the arrival time and when the stop counter was last updated — it cannot refresh while the app is asleep, and now that is honest. The progress bar follows the clock.

Thank you for every comment and review.

## What’s new (version 1.0)
First release: countdown in the Dynamic Island and on the Lock Screen, a notification one stop before you get off, line changes, station search, pinned routes, a Siri shortcut, GPS correction on above-ground sections, calibration mode and a trip journal. Fully offline.

## Notes for App Store Connect
- Add English as a second localization for the app listing; the primary one
  stays Ukrainian.
- Privacy Policy URL and Support URL are the same for both localizations:
  https://dayvan777.github.io/METRO/ (the page itself is bilingual).
- Screenshots: the store shows the Ukrainian set unless English ones are
  uploaded. The slides live in Figma
  (https://www.figma.com/design/nP5hsprVlSa0tB6hEUUx81) — duplicate the page,
  swap in screenshots taken with `-AppleLanguages "(en)"` and retype the
  captions. The app is fully translated, station names included.
