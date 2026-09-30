# Moments POS iOS 1.6.2 – splash logo fix

Ez a patch az 1.6.1-re épül.

Javítások:
- külön `SplashLogo.jpg` bundle erőforrás, hogy a SwiftUI betöltőképernyő biztosan meg tudja jeleníteni a Moments POS ikont;
- külön natív `LaunchScreen.storyboard`, középre helyezett Moments POS logóval;
- minimum 1,2 másodpercig látható alkalmazáson belüli splash, hogy gyors cache-es induláskor se villanjon át észrevétlenül;
- az 1.6.1 gesztusjavítása változatlanul megmarad.

Másold be az iosipa projektbe:
- project.yml
- Sources/MomentsPOST02App.swift
- Sources/POSWebView.swift
- Resources/SplashLogo.jpg
- Resources/LaunchScreen.storyboard

Fontos: az iOS a natív launch screent gyorsítótárazhatja. Ha frissítés után a legelső statikus képernyő még régi, az alkalmazáson belüli splash már az új logót mutatja. A natív cache frissülhet újraindítás után; ha tartósan nem, az app újratelepítése kényszeríti az új launch screen használatát.
