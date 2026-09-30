Moments POS iOS 1.7.4 – Performance & Smoothness

Ez a patch az 1.7.3 működő verziójára épül.

Fő változások:
- Nincs mesterséges minimum splash-idő: a loader azonnal eltűnik, amikor a Kassza DOM-ja használható.
- A WKWebView DOMContentLoaded jelzést küld natívan, ezért nem várunk minden távoli képre/fontfájlra.
- A splash biztonsági timeout 4,0 mp-ről 2,5 mp-re csökkent.
- A T02 automatikus keresése 0,85 mp-cel később indul, hogy az első képernyő betöltését ne terhelje.
- A Kassza navigációs betöltésjelzője fix 4 px sáv, ezért nem ugrál a webes felület.
- A Vonalkódok fül az utolsó, legfeljebb 6 órás terméklistát helyi cache-ből azonnal megjeleníti.
- A cache megjelenítése után a lista csendben frissül a WordPressből.
- Vonalkód-listánál 50 helyett 100 termék kerül lekérésre oldalanként.
- 32 MB memória + 128 MB lemez URL-cache a natív képekhez és URL-kérésekhez.
- A már működő T02 nyugta- és vonalkódnyomtatási motor nem változott.
- A Kassza WordPress HTML/CSS megjelenése nem változott.

Telepítés:
1. A ZIP teljes tartalmát másold az iosipa projektedbe.
2. Engedélyezd a felülírást.
3. GitHub Desktop Summary:
   Improve loading performance and smoothness
4. Commit to main -> Push origin.
5. GitHub Actions -> Run workflow.
6. Az új IPA-t SideStore-ral telepítsd a meglévő app fölé.

Verzió: 1.7.4
Build: 20
