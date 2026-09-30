# Moments POS iOS 1.6.1 – rendszer-gesztus javítás

Ez a patch kumulatív az 1.6.0 splash screen frissítéssel.

Változás:
- a kassza WKWebView böngésző jellegű vissza/előre swipe gesztusai ki vannak kapcsolva;
- a Moments POS nem kér rendszer-szélgesztus elsőbbséget;
- a splash screen és betöltő overlay változatlanul benne van;
- T02 nyugta- és vonalkódnyomtatási kódhoz nem nyúl.

Bemásolandó az iosipa projektbe:
- project.yml
- Sources/MomentsPOST02App.swift
- Sources/POSWebView.swift
- teljes Resources/Assets.xcassets mappa

GitHub Desktop Summary:
Fix iOS notification swipe gestures
