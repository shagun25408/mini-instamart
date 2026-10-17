import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ───────────────────────── Data & state ─────────────────────────
class Product {
  final int id;
  final String name, category, emoji;
  final double price;
  int stock;
  Product(this.id, this.name, this.category, this.price, this.stock, this.emoji);
}

class Order {
  final int id;
  final double total;
  int status; // 0 Placed, 1 Packed, 2 Out for delivery, 3 Delivered
  Order(this.id, this.total, this.status);
}

const categories = ['All', 'Fruits', 'Dairy', 'Snacks', 'Drinks'];
const steps = ['Order placed', 'Packed', 'Out for delivery', 'Delivered'];

class Store extends ChangeNotifier {
  final products = <Product>[
    Product(1, 'Bananas (1 dozen)', 'Fruits', 59, 20, '🍌'), Product(2, 'Apples (1 kg)', 'Fruits', 180, 12, '🍎'),
    Product(3, 'Oranges (1 kg)', 'Fruits', 90, 0, '🍊'), Product(4, 'Grapes (500 g)', 'Fruits', 75, 3, '🍇'),
    Product(5, 'Milk (1 L)', 'Dairy', 68, 30, '🥛'), Product(6, 'Curd (400 g)', 'Dairy', 45, 15, '🥣'),
    Product(7, 'Paneer (200 g)', 'Dairy', 90, 2, '🧀'), Product(8, 'Eggs (12)', 'Dairy', 96, 0, '🥚'),
    Product(9, 'Potato Chips', 'Snacks', 20, 50, '🥔'), Product(10, 'Cookies', 'Snacks', 35, 25, '🍪'),
    Product(11, 'Namkeen Mix', 'Snacks', 55, 10, '🥨'), Product(12, 'Chocolate Bar', 'Snacks', 50, 4, '🍫'),
    Product(13, 'Cola (750 ml)', 'Drinks', 40, 40, '🥤'), Product(14, 'Orange Juice (1 L)', 'Drinks', 110, 8, '🧃'),
    Product(15, 'Mineral Water (1 L)', 'Drinks', 20, 60, '💧'), Product(16, 'Iced Tea', 'Drinks', 45, 0, '🧋'),
  ];
  Map<int, int> cart = {};
  Order? order;
  String cat = 'All', query = '';
  late SharedPreferences _prefs;
  bool _tracking = false;

  Product byId(int id) => products.firstWhere((p) => p.id == id);
  int get cartCount => cart.values.fold(0, (a, b) => a + b);
  double get cartTotal => cart.entries.fold(0.0, (s, e) => s + byId(e.key).price * e.value);
  List<Product> get visible => products
      .where((p) => (cat == 'All' || p.category == cat) && p.name.toLowerCase().contains(query.toLowerCase()))
      .toList();

  // Persistence: cart, stock levels and the current order survive app restarts.
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString('state');
    if (raw != null) {
      final j = jsonDecode(raw);
      (j['stock'] as Map).forEach((k, v) => byId(int.parse(k)).stock = v);
      cart = (j['cart'] as Map).map((k, v) => MapEntry(int.parse(k), v as int));
      final o = j['order'];
      if (o != null) order = Order(o['id'], (o['total'] as num).toDouble(), o['status']);
    }
    _track();
  }

  void _save() => _prefs.setString('state', jsonEncode({
        'stock': {for (final p in products) '${p.id}': p.stock},
        'cart': cart.map((k, v) => MapEntry('$k', v)),
        'order': order == null ? null : {'id': order!.id, 'total': order!.total, 'status': order!.status},
      }));

  void setCat(String c) { cat = c; notifyListeners(); }
  void setQuery(String q) { query = q; notifyListeners(); }

  /// Change quantity by delta, capped at available stock.
  void change(Product p, int delta) {
    final n = ((cart[p.id] ?? 0) + delta).clamp(0, p.stock);
    n == 0 ? cart.remove(p.id) : cart[p.id] = n;
    _save();
    notifyListeners();
  }

  /// Re-validates stock, deducts it, creates the order, clears the cart.
  /// Returns the list of unavailable items (empty = success).
  List<String> place() {
    final bad = <String>[];
    for (final e in cart.entries) {
      final p = byId(e.key);
      if (p.stock < e.value) bad.add('${p.name} (${p.stock} left)');
    }
    if (cart.isEmpty || bad.isNotEmpty) return bad;
    final total = cartTotal;
    cart.forEach((id, q) => byId(id).stock -= q);
    order = Order((order?.id ?? 0) + 1, total, 0);
    cart = {};
    _save();
    notifyListeners();
    _track();
    return bad;
  }

  // Simulated delivery: advances one stage every 8 seconds (resumes after restart).
  Future<void> _track() async {
    if (_tracking) return;
    _tracking = true;
    while (order != null && order!.status < 3) {
      await Future.delayed(const Duration(seconds: 8));
      order!.status++;
      _save();
      notifyListeners();
    }
    _tracking = false;
  }
}

final store = Store();

// ───────────────────────── UI ─────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  runApp(MaterialApp(
    title: 'Instamart Mini',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepOrange),
    home: const HomePage(),
  ));
}

class QtyControl extends StatelessWidget {
  final Product p;
  const QtyControl(this.p, {super.key});
  @override
  Widget build(BuildContext context) {
    final n = store.cart[p.id] ?? 0;
    if (p.stock == 0) return const OutlinedButton(onPressed: null, child: Text('Out of stock'));
    if (n == 0) return FilledButton(onPressed: () => store.change(p, 1), child: const Text('ADD'));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(icon: const Icon(Icons.remove), onPressed: () => store.change(p, -1)),
      Text('$n', style: const TextStyle(fontWeight: FontWeight.bold)),
      IconButton(icon: const Icon(Icons.add), onPressed: n < p.stock ? () => store.change(p, 1) : null),
    ]);
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final ps = store.visible;
          return Scaffold(
            appBar: AppBar(title: const Text('Instamart Mini'), actions: [
              if (store.order != null)
                TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackPage())),
                    child: const Text('Track order')),
              IconButton(
                icon: Badge(
                    isLabelVisible: store.cartCount > 0,
                    label: Text('${store.cartCount}'),
                    child: const Icon(Icons.shopping_cart)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())),
              ),
            ]),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  onChanged: store.setQuery,
                  decoration: const InputDecoration(
                      hintText: 'Search groceries', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                  for (final c in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(c), selected: store.cat == c, onSelected: (_) => store.setCat(c)),
                    ),
                ]),
              ),
              Expanded(
                child: ps.isEmpty
                    ? const Center(child: Text('No products found'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 200),
                        itemCount: ps.length,
                        itemBuilder: (_, i) => ProductCard(ps[i]),
                      ),
              ),
            ]),
          );
        },
      );
}

class ProductCard extends StatelessWidget {
  final Product p;
  const ProductCard(this.p, {super.key});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(p.emoji, style: const TextStyle(fontSize: 44)),
            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('₹${p.price.toInt()}'),
            if (p.stock > 0 && p.stock <= 5)
              Text('Only ${p.stock} left', style: const TextStyle(color: Colors.deepOrange, fontSize: 12)),
            QtyControl(p),
          ]),
        ),
      );
}

class CartPage extends StatefulWidget {
  const CartPage({super.key});
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final addr = TextEditingController();
  String? error;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final lines = store.cart.keys.map(store.byId).toList();
          return Scaffold(
            appBar: AppBar(title: const Text('Cart')),
            body: lines.isEmpty
                ? const Center(child: Text('Your cart is empty 🛒'))
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      Expanded(
                        child: ListView(children: [
                          for (final p in lines)
                            ListTile(
                              leading: Text(p.emoji, style: const TextStyle(fontSize: 28)),
                              title: Text(p.name),
                              subtitle: Text('₹${p.price.toInt()} × ${store.cart[p.id]}'),
                              trailing: QtyControl(p),
                            ),
                        ]),
                      ),
                      Text('Total: ₹${store.cartTotal.toInt()}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                          controller: addr,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'Delivery address', border: OutlineInputBorder())),
                      const SizedBox(height: 4),
                      const Text('Payment: Cash on delivery (mock)', style: TextStyle(fontSize: 12)),
                      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: addr.text.trim().isEmpty
                              ? null
                              : () {
                                  final bad = store.place();
                                  if (bad.isEmpty) {
                                    Navigator.pushReplacement(
                                        context, MaterialPageRoute(builder: (_) => const TrackPage()));
                                  } else {
                                    setState(() => error = 'Not enough stock: ${bad.join(', ')}');
                                  }
                                },
                          child: const Text('Place order'),
                        ),
                      ),
                    ]),
                  ),
          );
        },
      );
}

class TrackPage extends StatelessWidget {
  const TrackPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final o = store.order;
          return Scaffold(
            appBar: AppBar(title: const Text('Order status')),
            body: o == null
                ? const Center(child: Text('No orders yet'))
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Order #${o.id} · ₹${o.total.toInt()}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      for (var i = 0; i < steps.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(children: [
                            Text(i <= o.status ? '✅' : '⚪', style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 12),
                            Text(steps[i], style: TextStyle(fontWeight: i == o.status ? FontWeight.bold : FontWeight.normal)),
                          ]),
                        ),
                    ]),
                  ),
          );
        },
      );
}
