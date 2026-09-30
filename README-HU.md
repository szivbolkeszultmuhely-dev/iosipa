Moments POS iOS 1.7.3 – embedded splash logo fix

A logó most két, egymástól független módon biztosított:
1) valódi iOS LaunchScreen: egy teljes képernyős LaunchBackground.png fájlba előre bele van sütve a logo;
2) appon belüli „Kassza betöltése…” réteg: a logo PNG-je base64-ként közvetlenül a Swift futtatható kódba van ágyazva, tehát nem függ asset/bundle névfeloldástól.

A dinamikus logó ZStack közepén van, ezért minden iPhone méreten középen marad.

Telepítés:
- a ZIP TELJES tartalmát másold az iosipa projektbe;
- engedélyezd a felülírást;
- GitHub Desktop Summary: Embed splash logo directly in app
- Commit -> Push -> GitHub Actions -> új IPA -> SideStore.
