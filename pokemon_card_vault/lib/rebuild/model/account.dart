enum AccountStatus { restoring, signedOut, authenticated, guest, unavailable }

class AccountUser {
  const AccountUser(
      {required this.id,
      required this.email,
      this.displayName = '',
      this.emailVerified = false});
  final String id, email, displayName;
  final bool emailVerified;
}

class AccountSession {
  const AccountSession({required this.status, this.user});
  final AccountStatus status;
  final AccountUser? user;
  bool get canBrowse =>
      status == AccountStatus.authenticated || status == AccountStatus.guest;
}

/// Errore tipizzato: la UI non riceve eccezioni o messaggi del backend.
class AccountFailure implements Exception {
  const AccountFailure(this.code);
  final String code;
  String get message => switch (code) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' =>
          'Email o password non corrette.',
        'invalid-email' => 'Inserisci un indirizzo email valido.',
        'missing-password' => 'Inserisci la password.',
        'user-disabled' => 'Questo account è stato disabilitato.',
        'too-many-requests' => 'Troppi tentativi. Riprova tra poco.',
        'network-request-failed' =>
          'Connessione non disponibile. Riprova oppure continua come ospite.',
        'operation-not-allowed' =>
          'Questo metodo di accesso non è disponibile.',
        'google-configuration' =>
          'Google non riconosce questa build Android. Occorre verificare package e impronta SHA-1 in Firebase.',
        'google-sign-in-failed' =>
          'Accesso Google non riuscito. Riprova tra poco.',
        'account-exists-with-different-credential' =>
          'Questa email è associata a un altro metodo di accesso.',
        'unauthorized-domain' =>
          'Questo dominio non è autorizzato per il login Firebase.',
        'popup-blocked' =>
          'Il browser ha bloccato la finestra Google. Consenti il popup e riprova.',
        'invalid-name' => 'Inserisci un nome tra 2 e 60 caratteri.',
        _ => 'Operazione non riuscita. Riprova tra poco.',
      };
}

class AccountProfile {
  const AccountProfile(
      {this.displayName = '', this.username = '', this.walletAddress = ''});
  final String displayName, username, walletAddress;
  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
      displayName: '${json['displayName'] ?? ''}',
      username: '${json['username'] ?? ''}',
      walletAddress: '${json['walletAddress'] ?? ''}');
}

class AccountBalance {
  const AccountBalance({required this.available, required this.locked});
  final double available, locked;
  factory AccountBalance.fromJson(Map<String, dynamic> json) => AccountBalance(
      available: (json['availablePkn'] as num?)?.toDouble() ?? 0,
      locked: (json['lockedPkn'] as num?)?.toDouble() ?? 0);
}

class AccountOrder {
  const AccountOrder(
      {required this.id,
      required this.status,
      required this.total,
      this.createdAt});
  final String id, status;
  final double total;
  final DateTime? createdAt;
}
