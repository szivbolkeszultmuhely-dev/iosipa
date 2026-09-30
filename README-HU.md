# Moments POS iOS 1.8.0 – Reliability Update

Ez a kiadás a validált 1.7.4 Performance & Smoothness verzió teljes forrására épül.
A működő T02 rasztermotorok és a Kassza webes dizájnja nem lett újratervezve.

## Újdonságok

1. **Release / rollback alap** – verziózott 1.8.0 (build 21), külön rollback csomaggal és SHA256 manifesttel.
2. **Dupla nyugta elleni védelem** – a WordPress oldali idempotencia mellé tartós draft/tranzakciókulcs-mentés és `transaction-status` visszaellenőrzés került.
3. **Kézi nyomtatási retry** – megszakadt nyugta- vagy címkenyomtatás helyben megmarad. Soha nincs automatikus újranyomtatás; a felhasználó dönt.
4. **Üzemi napló** – Beállításokban az utolsó 20 kasszatranzakció és az utolsó 20 natív app/nyomtatási esemény.
5. **Rendszerállapot** – WordPress plugin, API séma, WooCommerce, szolgáltató, HTTPS, titkosítás, archív tárhely, T02.
6. **App–plugin kompatibilitás** – API séma és minimum appverzió ellenőrzés, figyelmeztetéssel.
7. **Félbehagyott kosár helyreállítása** – 12 órás helyi draft; visszatöltéskor a szerver újraellenőrzi az aktuális árat és készletet.
8. **SideStore aláírásfigyelés** – ha az embedded provisioning lejárata olvasható és legfeljebb ~2 nap van hátra, induláskor és a Beállításokban figyelmeztet.
9. **Opcionális Face ID / készülékkód appzár** – induláskor és legalább 5 perc háttérben töltött idő után.
10. **Vonalkód Kedvencek / Legutóbbi** – csillagozható címkék és az utolsó 20 nyomtatott termék gyorsszűrője.

## Szükséges WordPress plugin

Moments POS Commercial Core **0.4.0-beta** (API séma 2).

## Telepítés

1. Készíts WordPress-mentést, majd telepítsd/frissítsd a **0.4.0-beta** plugin ZIP-et.
2. A projekt teljes tartalmát másold az `iosipa` repóba, a mappastruktúrát megtartva.
3. GitHub Desktop Summary: `Add Moments POS 1.8.0 reliability update`
4. Commit → Push origin.
5. GitHub Actions → `Build Moments T02 test IPA (unsigned)` → Run workflow.
6. Az IPA-t SideStore-ból telepítsd a meglévő app fölé.

A plugin telepítése kerül előre, hogy az 1.8.0 app első indulásakor már elérhető legyen az API séma 2 és a megbízhatósági végpontok.

## Ajánlott első teszt

- Kassza megnyílik és belépés megmarad.
- Egy próbakosár felépítése után app bezár/újranyit → kosár visszaáll.
- Beállítások → Rendszerállapot: plugin 0.4.0-beta / API 2 / kompatibilis.
- T02 próba nyomtatás.
- Vonalkódcímke nyomtatás, Kedvenc és Legutóbbi szűrő.
- Egy éles, kis összegű kontrollált nyugta → eredeti PDF → T02.
- Face ID csak ezután kapcsold be opcionálisan.

Verzió: 1.8.0
Build: 21
