# Scanner mobile Rebuild

La scheda Scansiona apre `presentation/scanner/scanner_screen.dart` e permette
di scegliere Collezione o Listing. Entrare nella scheda non apre la fotocamera:
Ready avvia fotocamera e riconoscimento. Tornando da un'altra schermata viene
nuovamente richiesto Ready; le bozze restano nel controller durante la navigazione.

Dopo Ready le carte vengono raccolte continuamente, senza tocchi sui risultati.
Due rilevamenti consecutivi accettano una carta; tenerla inquadrata non aggiunge
altre copie. Due frame senza carta o una carta diversa riarmano il conteggio.
Ogni riga conserva fino a tre candidati e i migliori score osservati. Aprire la
linguetta mette in pausa il riconoscimento e permette di scegliere la stampa,
condizioni, lingua, finitura, quantità e prezzo PK. Chiuderla riprende la scansione.

Le carte raccolte sono bozze. Il pulsante Conferma nella linguetta salva il
possesso o pubblica i listing: il semplice riconoscimento non certifica il
possesso. Il prezzo è facoltativo per la collezione e obbligatorio per i listing.

## Struttura

- `model/scanner.dart`: frame copiati, candidati, articoli, dati di mercato e gruppo.
- `constants/scanner_constants.dart`: condizioni e lingue del contratto API.
- `controller/scanner_controller.dart`: Ready, raccolta continua, revisione, prezzi,
  sessione, ripristino e conferma.
- `service/scanner_service.dart`: identità, suggerimenti e validazione del salvataggio.
- `provider/scanner_provider.dart`: richieste autenticate e verifica del possesso.
- `provider/scanner_market_provider.dart`: metadati e prezzi pubblici.
- `provider/scanner/`: motore nativo, provisioning e log portati da old.
- `presentation/scanner/component/`: fotocamera, linguetta ed editor.
- `style/scanner_style.dart`: palette.

Il Rebuild non importa old. Usa il canale pokoin.scan/engine e il pacchetto
Android CNN incluso nell'APK. I frame YUV420/BGRA conservano stride e orientamento;
vengono copiati solo quando il controller può riconoscerli, con una richiesta in
corso e timeout di 20 secondi. La galleria attuale è western; solo gli ID ct_id
sono raddoppiati una volta per ottenere l'ID pubblico. Lingua e finitura richiedono
la verifica dell'utente.

## Prezzo indicativo

La revisione richiede GET /api/marketplace-card-sales?cardId=...&slices=1 e
GET /api/marketplace-card-page?cardId=... . Le vendite usano le stesse priorità
del codice web scan-pricing.js: condizione/lingua/finitura, poi condizione vicina
e ripiego su altre lingue preferendo EN, con osservazioni recenti e non gradate.
Se mancano vendite adatte viene usato il prezzo generale della carta.

Il campo è precompilato come Suggerito dal mercato e resta modificabile.
Cambiare stampa o caratteristiche ricalcola il suggerimento; un prezzo manuale
non viene sovrascritto da risposte arrivate dopo la modifica. Il pulsante Usa
prezzo indicativo permette di riprendere il suggerimento. L'assenza dei prezzi
non impedisce di salvare la collezione. I metadati sono caricati in gruppi di tre,
con cache di cinque minuti e massimo 64 carte, senza richieste per ogni frame.

## Salvataggio e verifica

La raccolta dalla fotocamera resta in memoria, senza mutazioni remote durante
la scansione. Le bozze e le modifiche non sopravvivono alla chiusura del processo
e vengono svuotate al cambio account. Gli ospiti possono riconoscere le carte;
devono accedere prima di salvare.

POST /api/scan-session?action=start recupera il gruppo aperto dell'account.
Eventuali righe web recuperate vengono mostrate e richiedono revisione prima
della conferma. Ogni bozza viene aggiunta con action=add e il suo ID locale è
sostituito dall'ID remoto confermato. I campi, compreso cardId quando si sceglie
un altro candidato, passano attraverso action=item; action=submit usa una chiave
stabile per gruppo. intent=collection salva il possesso senza listing;
intent=list registra il possesso e pubblica solo su Pokoin.

La risposta submit deve confermare stato submitted, intento e possesso.
Dopo la conferma viene letta l'API privata marketplace-collection e verificata
la presenza dei documenti scan:<itemId> per gli ID canonici selezionati.
Solo allora la lista si svuota e Cardex/Portfolio ricaricano la collezione.
Un HTTP 200 vuoto non viene trattato come successo. Se il gruppo è già inviato,
il tentativo successivo verifica il possesso senza pubblicare altre copie.
Durante una conferma incerta la destinazione e le righe restano bloccate.

Un'aggiunta dalla risposta incerta richiede Ricarica. Le nuove righe remote sono
confrontate con quelle note prima della richiesta; una corrispondenza univoca
sostituisce la bozza senza ripetere l'aggiunta. Una situazione ancora ambigua
resta da verificare; non viene ritentata automaticamente. Le richieste private
usano il bearer Firebase; nessuna scrittura client diretta in Firestore.

## Verifica

test/rebuild/scanner_test.dart copre Ready, raccolta continua, deduplicazione,
pausa, primi candidati, prezzi, risposta submit, lettura del possesso, tentativi
ripetuti, cambio account e layout a 390×844 con testo ingrandito. I test widget
sostituiscono la fotocamera. La verifica usa una copia isolata con le dipendenze
del Rebuild, poiché il grafo principale richiede un compilatore C Windows per
l'hook win32 6. Riconoscimento reale e salvataggio con l'account sul telefono
richiedono una prova sul dispositivo; non vengono simulati come verificati.
