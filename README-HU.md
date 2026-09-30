# Moments POS iOS 1.7.1 – splash, tabbar és rendszer-gesztus javítás

Kumulatív patch az 1.7.0 fölé.

## Javítások

- A felhasználó által újra feltöltött Moments POS ikon közvetlenül az Asset Catalogba került `SplashLogo` néven.
- A natív LaunchScreen és az appon belüli betöltőoverlay ugyanazt az assetet használja.
- Az AppIcon készlet is a feltöltött eredeti ikonból lett újragenerálva.
- Moments témában az alsó tabbar világos lilás hátteret, sötétlila kiválasztott és sötét szürkés-lila nem kiválasztott ikon/feliratszínt kapott.
- A tabbar UIKit megjelenése explicit be van állítva, hogy az újabb iOS anyaghatások se mossák el a feliratokat.
- A WebView böngésző-vissza/előre gesztusa továbbra is kikapcsolt.
- A teljes app explicit nem kér rendszer-szélgesztus elsőbbséget (`defersSystemGestures(on: [])`).
- A rendszer overlayek láthatósága explicit `.visible`.
- A WKWebView görgetőgesztusa nem törli/delayeli agresszíven a touch eseményeket.

## Nem változott

- Kassza webes belseje / WordPress CSS
- Billingo PDF → T02 nyomtatás
- validált T02 raster motor
- Vonalkódcímke nyomtatás és feed
- WordPress API

## Telepítés

A ZIP teljes tartalmát másold a meglévő `iosipa` repo gyökerébe, a mappastruktúrát megtartva, majd engedélyezd a felülírást.

GitHub Desktop Summary:

`Fix splash logo, tab bar contrast and system gestures`
