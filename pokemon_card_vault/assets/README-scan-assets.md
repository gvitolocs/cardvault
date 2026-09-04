# On-device scan assets (not in git)

Sync from pokoin-cardapp before Android release builds on nezopt:

```bash
rsync -a --delete \
  /home/nez/Projects/pokoin-cardapp/flutter/assets/models/ \
  /home/nez/Projects/cardvault/pokemon_card_vault/assets/models/
rsync -a --delete \
  /home/nez/Projects/pokoin-cardapp/flutter/assets/milo_index/ \
  /home/nez/Projects/cardvault/pokemon_card_vault/assets/milo_index/
rsync -a --delete \
  /home/nez/Projects/pokoin-cardapp/flutter/assets/milo_cnn_index/ \
  /home/nez/Projects/cardvault/pokemon_card_vault/assets/milo_cnn_index/
```

Release AAB (nezopt): `dist/pokoin-1.0.0+58.aab`
