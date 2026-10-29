# Scanner mobile Rebuild

Lo scanner offre Single e Batch. Ready avvia la fotocamera; entrare nella scheda
non la accende automaticamente. Il motore nativo, la stabilizzazione su due
osservazioni e i primi tre candidati restano condivisi tra le due modalità.

## Single

Una carta riconosciuta mette in pausa la scansione, salva una bozza locale in
Clipboard e apre il dettaglio con Prezzo e listing prima dell'immagine, sui
telefoni. Condizione, lingua, finitura, quantità e prezzo vengono precompilati.
Tornando allo scanner serve di nuovo Ready: nessuna ripresa automatica.
Se il salvataggio locale fallisce, la carta rimane nella linguetta e il dettaglio
non viene aperto come se il trasferimento fosse riuscito.

## Batch

La raccolta continua finché l'utente apre la linguetta o lascia la schermata.
Tenere una carta inquadrata non aggiunge copie; due frame vuoti o una carta
diversa riarmano il conteggio. La linguetta consente di scegliere tra i primi tre
risultati, modificare caratteristiche, quantità e prezzo, e rimuovere una bozza.

Save è visibile e disabilitato. Copy to Clipboard scrive uno snapshot locale
atomico e svuota le righe trasferite solo dopo la conferma del disco. Non chiama
scan-session, scan-batch, Firestore o API di pubblicazione. Un errore conserva
le righe per ritentare. Il prezzo può essere lasciato vuoto; i suggerimenti lenti
non devono impedire di copiare le bozze (attesa limitata a due secondi).
Toccare il titolo di una carta nella linguetta trasferisce quella riga e ne apre
il dettaglio, lasciando le altre scansioni da controllare.

## Clipboard persistente

L'icona si trova all'estrema destra della barra superiore, dopo i filtri, ed è
presente anche nei dettagli reali. Il badge conta le bozze da controllare o
listare, non la somma delle copie. Un trasferimento riuscito aggiorna il badge e
fa ingrandire/rimpicciolire brevemente l'icona. Le righe pubblicate rimangono
consultabili con stato Pubblicata, ma escono dal contatore delle cose da fare.

La lista conserva sul dispositivo ID canonico, candidati/score, metadati,
condizione, lingua, finitura, quantità, testo del prezzo, suggerimento e ulteriori
campi del listing. Ogni cattura ha un ID univoco anche tra riavvii. Gli snapshot
Hive sono versionati e separati per ospite/account, con UID hash nel nome del
box e un singolo valore JSON. Gli account non ereditano automaticamente le
bozze altrui. Il login richiesto dal dettaglio di una bozza ospite può importare
quella sola bozza nell'account scelto esplicitamente.

Gli aggiornamenti sono serializzati sullo snapshot più recente, così modifiche
ravvicinate a campi diversi non si sovrascrivono. Una lettura fallita impedisce
le scritture e mostra Riprova Clipboard, invece di sostituire le bozze con una
lista vuota. I risultati tardivi di un vecchio account non ripopolano quello
attuale. Le bozze non trasferite nella linguetta sono ancora in memoria: per
conservarle dopo la chiusura usare Copy to Clipboard.

## Prezzo e pubblicazione singola

Il dettaglio aperto da Clipboard usa un form dedicato, con modifiche locali
persistenti e prezzo in PK. La pubblicazione avviene solo premendo Pubblica su
Pokoin dopo l'accesso, tramite POST /api/marketplace-listings: un oggetto per
carta, quantityAvailable da 1 a 99 e targets Pokoin=true/CardTrader=false.
Il prezzo deve essere positivo; le carte gradate richiedono società, voto e
numero di certificazione. Con Spedizione attiva serve il Paese da cui si
spedisce (`shipFromCountry`); Posizione e commento restano facoltativi.
La bozza non certifica il possesso in collezione.

Il form recupera come valore iniziale il Paese dell'indirizzo predefinito
dell'account (GET /api/account-addresses senza reveal), oppure del primo
indirizzo se nessuno è predefinito; in assenza usa GET
/api/marketplace-seller-settings. Non deduce il Paese dalla lingua della carta.
Il Paese è modificabile e persiste nella bozza; una scelta manuale non viene
sovrascritta da una risposta tardiva. Gli indirizzi sono gestibili da Profilo
→ Impostazioni account → Indirizzi di spedizione, come documentato in
rebuild-account.md.

Solo Pubblica salva il Paese nel profilo venditore tramite POST
/api/marketplace-seller-settings, verifica la conferma e poi invia il singolo
listing con sellerCountry/shipFromCountry e game=pokemon. Se la prima richiesta
fallisce non parte la POST del listing e la bozza resta modificabile.
I dettagli di gradazione sono null quando non applicabili. Gli HTTP 4xx mostrano
il motivo di validazione restituito dal server, con token rimossi e lunghezza
limitata; gli errori 5xx non espongono il corpo interno del servizio.

L'HTTP 400 visto sul telefono il 2026-10-21 non conservava il corpo della risposta.
Il form web pubblico attuale richiede il Paese e certificazione per carte gradate:
questi requisiti mancavano nel mobile. Questo identifica omissioni concrete, ma
non dimostra retroattivamente quale validazione abbia causato quel 400 né una
correzione del servizio Rust. Le verifiche di pubblicazione sono simulate.

Il marcatore publishing viene scritto prima della POST. Il doppio tocco non
crea due richieste. Una risposta deve identificare annuncio, carta, proprietario
e sourceListingId della bozza; una risposta vuota non è successo. Risposte perse,
errori server o riavvii durante la pubblicazione producono uno stato incerto:
Verifica pubblicazione esegue soltanto una GET dei listing del proprietario e
cerca il sourceListingId. Non ripete automaticamente la POST. Un annuncio
verificato è escluso dai lavori da fare. Il form dimostrativo delle altre route
catalogo rimane distinto dal form delle bozze scanner.

## Prezzo indicativo e motore

La revisione usa GET /api/marketplace-card-sales?cardId=...&slices=1 e
GET /api/marketplace-card-page?cardId=..., privilegiando condizione, lingua,
finitura, campioni recenti non gradati e ripiego sul prezzo generico. Un prezzo
manuale non è sovrascritto. Il motore continua a usare pokoin.scan/engine, il
pacchetto CNN Android e frame YUV420/BGRA con stride/orientamento. Solo gli ID
nativi ct_id sono raddoppiati per ottenere l'ID pubblico; il Rebuild non importa old.

## Struttura e verifica

- model/scanner.dart e listing_draft.dart: catture, dati serializzabili e stati.
- controller/scanner_controller.dart: Ready, Single/Batch, revisione e trasferimento.
- controller/scan_clipboard_controller.dart: scope, modifiche ordinate e pubblicazione.
- service/scan_clipboard_service.dart: persistenza e validazione/coordinamento API.
- provider/scan_clipboard_provider.dart: snapshot Hive; draft_listing_provider.dart:
  POST singola e GET di riconciliazione autenticate.
- presentation/shared/component/scan_clipboard_button.dart e scan_clipboard_sheet.dart:
  badge animato e lista; card_details/component/draft_listing_composer.dart: form.
- test/rebuild/scan_clipboard_test.dart: riapertura reale Hive, isolamento account,
  errori disco/lettura, modifiche concorrenti, Single/Batch, badge, precompilazione,
  prezzo offline, doppio tocco e riconciliazione dopo risposta persa.

I test Rebuild usano la copia isolata con le dipendenze del client perché l'hook
win32 del grafo principale richiede un compilatore C Windows. Le prove di POST
sono simulate: nessun listing è stato pubblicato per verificare la modifica.

## Salvataggio diretto precedente

Il codice Scan Connect è mantenuto come riferimento, ma il flusso attuale non
espone il vecchio comando di conferma. La prova del 2026-10-19 mostrava ancora
HTTP 500 in action=item prima di submit; questo cambio di UX non certifica una
correzione del backend. Il payload cardId senza confirm evita il difetto locale
delle assegnazioni SQL duplicate a reviewed, coperto da
api/_scan_store_mobile_patch.test.js. Save resta disabilitato in attesa della
risoluzione del servizio. Nessun deploy o cambiamento di schema è incluso.
