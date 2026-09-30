Moments POS iOS 1.7.2 – ellenőrzött launch screen javítás

Ez a csomag az 1.7.1-re épül, és annak UI/gesztus/tabbar javításait megtartja.

Launch screen javítás:
- A Moments POS logó NEM külön képelemként töltődik.
- A logó fizikailag rá van sütve egy teljes képernyős lila háttérképre.
- A natív iOS LaunchScreen.storyboard ezt az egyetlen, teljes képernyős képet használja.
- Az app indulás utáni SwiftUI betöltőrétege is ugyanazt a LaunchComposite képet használja.
- scaleAspectFill / scaledToFill miatt a kép közepe minden iPhone-méreten a képernyő közepén marad.
- Nincs SplashLogo hivatkozás a projektben.

Verzió: 1.7.2 (build 18)

Telepítés:
1. A ZIP teljes tartalmát másold az iosipa repo gyökerébe.
2. Engedélyezd a felülírást.
3. GitHub Desktop Summary: Fix launch screen with baked centered logo
4. Commit -> Push origin.
5. GitHub Actions -> Run workflow.
6. Az új IPA-t SideStore-ral telepítsd a meglévő app fölé.

Megjegyzés: az iOS a natív launch screen pillanatképét cache-elheti. Verzió/build emelés megtörtént; ha az első indítás még korábbi képet mutat, zárd be teljesen az appot és indítsd újra. Az appon belüli betöltőréteg már biztosan a LaunchComposite képet használja.
