# Moments POS iOS 1.7.0 – Visual Refresh

Ez egy kumulatív iOS patch a jelenlegi működő Moments POS fölé.

## Mi változik?
- új **Moments** natív téma (lila/pink, világosabb kártyák)
- **Kontrasztos** mód
- **Rendszer** mód
- jobb felső **Beállítások** fogaskerék a Kassza / T02 próba / Vonalkódok képernyőn
- nagyobb natív betűméret kapcsoló
- márkázott betöltőanimáció be/ki
- T02 automatikus keresés appindításkor be/ki
- T02 és WordPress állapot + appverzió a Beállításokban
- új, egységes márkázott felső sáv
- színesebb alsó tabbar
- újradizájnolt **T02 próba** natív képernyő
- újradizájnolt **Vonalkódok** natív képernyő
- tartalmazza az 1.6.2 splash-logo és gesture javítást
- tartalmazza a validált 1.5.1 vonalkód-címke papírtovábbítást

## Mi NEM változik?
- A WordPressből betöltött **Kassza belső HTML/CSS felülete változatlan**.
- A validált T02 nyugta-raszter és Bluetooth transport nem lett átírva.
- A Billingo/PDF nyomtatási logikát nem módosítja.

## Bemásolandó fájlok
Másold az `iosipa` projektedbe a ZIP teljes tartalmát, a mappastruktúrát megtartva:

- `project.yml`
- `Sources/AppAppearance.swift` (új)
- `Sources/MomentsUI.swift` (új)
- `Sources/MomentsPOST02App.swift`
- `Sources/POSWebView.swift`
- `Sources/BarcodeLabelsView.swift`
- `Sources/TestView.swift`
- `Sources/T02BarcodeLabelRaster.swift`
- `Resources/SplashLogo.jpg`
- `Resources/LaunchScreen.storyboard`
- `Resources/Assets.xcassets/...`

Felülírás: igen.

## GitHub Desktop Summary
`Add Moments POS visual refresh and appearance settings`

Majd: Commit → Push origin → GitHub Actions → Run workflow → IPA → SideStore.

## Verzió
- 1.7.0
- build 16
