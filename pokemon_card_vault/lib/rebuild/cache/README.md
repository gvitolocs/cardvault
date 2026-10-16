# Cache Rebuild

- `marketplace_home_cache.dart`: snapshot versionato dei due caroselli, massimo
  12 espansioni e 12 carte. Le due sezioni hanno date indipendenti e vengono
  conservate per 7 giorni. Al riavvio sono mostrate prima dell'aggiornamento.
  Una copia completa salvata da meno di 5 minuti viene riutilizzata senza GET;
  Riprova forza l'aggiornamento. Una copia parziale non evita il caricamento.
  Il ripristino attende al massimo 280 ms: letture come quelle da 252–260 ms
  misurate sul telefono possono completarsi senza richieste ai metadati.
  Appena la lettura termina si prosegue, senza un'attesa fissa di 280 ms.
- `marketplace_image_cache.dart`: unica istanza della cache immagini, massimo
  80 file e rimozione dei file non utilizzati per 30 giorni. I widget lazy
  richiedono le immagini nel viewport, senza margine di precache
  dell'intero catalogo.
  Il manager consente al massimo 2 download contemporanei.
- `marketplace_search_cache.dart`: cache solo in memoria per 30 secondi,
  massimo 16 pagine riuscite e due cataloghi artista preparati. Le chiavi delle
  pagine comprendono testo, lingua, tipo di articolo, offset e limite. Una
  ricerca ripetuta fresca ricompare subito; invio e Riprova aggiornano la pagina.
  Non conserva gli errori e si perde quando l'app viene chiusa.

I DAO sotto `provider/` gestiscono directory e file. Le cache su disco risiedono nella
cartella privata di supporto dell'app, sotto `rebuild-cache/metadata/` e
`rebuild-cache/images/`, e sopravvivono ai normali riavvii. Cancellare i dati
dell'app o disinstallarla elimina anche la cache. La cache è una copia di
presentazione: l'API resta la fonte per gli aggiornamenti.

L'entry point Rebuild carica automaticamente la discovery all'apertura:
i contenuti salvati sono ripristinati prima delle richieste di aggiornamento.
Una copia completa recente evita le GET dei metadati; al primo avvio serve
la rete. Le immagini restano lazy, con massimo due download contemporanei.
`autoLoadDiscovery: false` rimane disponibile per i test diagnostici, ma
non è usato dall'entry point dell'app.
