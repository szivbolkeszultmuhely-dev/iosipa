# Moments POS – AIMO T02 – natív iOS teszt (1/6)

Ez az **első tesztalkalmazás**, nem a teljes Moments POS. Egy natív iPhone-alkalmazás közvetlenül megkeresi a T02-t, kapcsolódik Bluetoothon és **NEM ÉRVÉNYES NYUGTA** feliratú próbanyomatot küld. Nem tartalmaz semmilyen fizetős SDK-t, telemetriát, felhős kiszolgálót vagy külső nyomtatóalkalmazást.

A T02-nél ismert protokollt (`FF00` szolgáltatás / `FF02` írási jellemző, ESC/POS jellegű `GS v 0` 384 px raszter) implementálja. Ez még **nem bizonyítottan működik az AIMO T02 konkrét hardvereden**: azt a telefonodon kell kipróbálni. Sikertelen kapcsolat esetén másold ki a beépített naplót.

## Windows → iOS IPA előállítása díjmentesen

* Ha még nincs, készíts ingyenes GitHub-fiókot és telepítsd a **GitHub Desktop** Windows-verzióját.
* A projektet bontsd ki Windows alatt egy mappába. **Ne tölts fel ide jelszót, Apple ID-t, személyes dokumentumot vagy a zárt Moments POS kódját.** Ebben az 1. lépéses projektben egyik sincs.
* GitHub Desktop → File → Add local repository; ha a mappa még nem Git-repository, ajánlja fel a `create a repository here` lehetőséget. Készíts commitot, majd `Publish repository` — **Public** (nyilvános). Így a szabványos GitHub Actions macOS-fordítás díjmentes. A teljes tesztalkalmazás forráskódja nyilvános lesz.
* A GitHub webes repóban → **Actions** → `Build Moments T02 test IPA (unsigned)` → `Run workflow`. Ha a GitHub első alkalommal engedélyezést kér, engedélyezd a saját workflow használatát.
* Sikeres fordítás után a futás alján az **Artifacts → MomentsPOST02-unsigned** állományt töltsd le és csomagold ki. A benne lévő `MomentsPOST02-unsigned.ipa` a telefonra szánt, **még nem aláírt** alkalmazáscsomag.

Ha a workflow `xcodebuild` lépésénél piros hibát kapsz, másold be a hibát: ebben a környezetben Linux alatt a Swift-szintaxis ellenőrizhető, de az Apple SDK és az Xcode-os teljes fordítás nem futtatható.

## Telepítés: SideStore

A SideStore hivatalos, naprakész Windows-telepítési útmutatója: https://docs.sidestore.io/docs/installation/install

Első alkalommal Windows-számítógép és USB-kábel szükséges a SideStore telepítéséhez. Ezután a SideStore használatával importálható a fenti **unsigned IPA**. A SideStore a saját Apple-fiókoddal aláírja az alkalmazást. Az ingyenes aláírás hét napig érvényes; **lejárat előtt** a SideStore + az útmutatójában előírt VPN segítségével telefonról frissíthető. Rendszerfrissítés, kijelentkezés vagy párosításvesztés esetén még szükség lehet a Windowsra. Az ingyenes Apple-fióknál az aktív sideloadolt alkalmazások száma is korlátozott.

Fontos: a SideStore a telepítés/megújítás segédje, **nyomtatáskor nem kell megnyitni**.

## Teszt a telefonon

1. Kapcsold be a T02-t, és engedélyezd az iPhone Bluetooth-hozzáférését a Moments T02 tesztnek.
2. Nyomd meg a `T02 keresése` gombot, majd válaszd a megjelenő T02-t.
3. Várd meg a `T02 nyomtatásra kész` státuszt, majd nyomd meg a `TESZT nyomtatása` gombot.
4. Ellenőrizd, hogy a teljes tesztkép kijött-e a papírra. Az `Az adatok elküldve` állapot önmagában nem bizonyít sikeres fizikai nyomtatást.
5. Ha nem működik, koppints a `Napló másolása` gombra és küldd el a naplót. Ne küldj mellé jelszót, nyugtát vagy személyes adatot.

**Egyetlen éles nyugtát se nyomtass ezzel a verzióval.** A 2–4. lépésben következik a webes kassza, az eredeti PDF hibátlan raszterezése és az egygombos POS-nyomtatás.

## Műszaki háttér / hivatkozások

- Nyílt forrású, MIT licencű T02 iOS mintaprojekt: https://github.com/matheusdanoite/Phomemo-Swift
- Másik támogatott T02 referencia: https://github.com/transcriptionstream/phomymo
- SideStore hivatalos dokumentáció: https://docs.sidestore.io/
- GitHub standard public runner: https://docs.github.com/en/actions/reference/runners/github-hosted-runners

Nincs beemelt harmadik féltől származó forráskódfájl. A protokollparamétereket és architektúrát a fenti nyilvános implementációk alapján alakítottuk ki.
