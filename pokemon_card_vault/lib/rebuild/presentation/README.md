# Presentation

La presentazione è organizzata per schermata:

```text
presentation/
├── card_details/
│   ├── card_details.dart
│   ├── component/    # header, artwork, grafico, vendita, Shop e offerte
│   └── atomics/      # contenitore, badge, campi, filtri e immagine
├── marketplace/
│   ├── marketplace_screen.dart
│   ├── component/    # discovery, ricerca, filtri, espansioni, slider e tile
│   └── atomics/      # risultato ricerca e snapshot della miniatura
└── shared/
    ├── component/    # carrello e navigazione
    ├── atomics/      # miniatura e illustrazione demo
    ├── price_format.dart
    └── marketplace_image_url.dart
```

Il Dart della schermata compone i component e collega stato, azioni e routing.
I component sono sezioni intermedie costruite con atomics. Gli atomics sono
mattoncini piccoli e riutilizzabili; quelli usati da più schermate vivono in
`shared/atomics/`. Un componente condiviso può osservare il suo controller,
come il carrello, senza accedere direttamente ai servizi.

Palette e temi restano in `lib/rebuild/style/`. Le cartelle `controller/`,
`service/`, `provider/` e `model/` mantengono le responsabilità dei dati e
dello stato esterne alla presentazione.

`marketplace/component/marketplace_suggestions.dart` è il widget separato dei
suggerimenti: riceve stato e callback da `MarketplaceSearch`, senza accedere
ai servizi. Compare con il campo attivo, mostra nomi/espansioni/artisti e fino
a sei versioni dal risultato API già richiesto dalla ricerca. L'atomic
`marketplace/atomics/suggestion_card_tile.dart` mostra nome, numero, espansione
e miniatura tramite `MarketplaceThumbnail`, mantenendo cache e segnaposto.
Il tocco apre la versione scelta e può passare la palette della miniatura.
Il motore locale lavora fuori dall'interfaccia; la lista costruisce le righe
visibili e si adatta allo spazio disponibile e al testo ingrandito.
