import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pages/home_page.dart';
import 'pages/cart_page.dart';
import 'pages/orders_page.dart';
import 'models/cart.dart';
import 'models/wallet.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PokecoinApp());
}

class PokecoinApp extends StatelessWidget {
  const PokecoinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Cart>(create: (_) => Cart()),
        ChangeNotifierProvider<Wallet>(create: (_) => Wallet()),
      ],
      child: MaterialApp(
        title: 'Pokecoin',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        initialRoute: '/',
        routes: {
          '/': (context) => const HomePage(),
          '/cart': (context) => const CartPage(),
          '/orders': (context) => const OrdersPage(),
        },
      ),
    );
  }
}
