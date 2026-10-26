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
  double get handlingFee => cart.isEmpty ? 0 : 3;
  double get deliveryFee => cart.isEmpty || cartTotal >= 99 ? 0 : 25;
  double get payable => cartTotal + handlingFee + deliveryFee;
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
    final total = payable;
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
const grad = LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF4F6D)], begin: Alignment.topLeft, end: Alignment.bottomRight);
const orange = Color(0xFFFF6A3D);
const bg = Color(0xFFF6F6F9);
const tint = Color(0xFFFFF1EA);
const catEmoji = {'All': '🛒', 'Fruits': '🍎', 'Dairy': '🥛', 'Snacks': '🍪', 'Drinks': '🥤'};

BoxDecoration cardBox([double r = 16]) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(r),
    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4))]);

InputDecoration fieldDeco(String hint, IconData icon, {Color fill = bg}) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: orange),
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none));

void go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

Widget billRow(String a, String b, {bool bold = false, Color? color}) {
  final s = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 17 : 14, color: color);
  return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(a, style: s), Text(b, style: s)]));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  runApp(MaterialApp(
    title: 'Instamart Mini',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: orange, scaffoldBackgroundColor: bg),
    // On a wide screen (Chrome / desktop) show the app inside a phone-shaped frame.
    builder: (context, child) => Container(
      color: const Color(0xFF16161A),
      alignment: Alignment.center,
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth < 600) return child!;
        final h = c.maxHeight - 32;
        return Container(
          width: 390,
          height: h < 844 ? h : 844,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(40), border: Border.all(color: Colors.black, width: 9)),
          child: child,
        );
      }),
    ),
    home: const LoginPage(),
  ));
}

class GradButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const GradButton(this.text, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .45 : 1,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
                gradient: grad,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x59FF6A3D), blurRadius: 14, offset: Offset(0, 6))]),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Container(
                  height: 54,
                  alignment: Alignment.center,
                  child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
            ),
          ),
        ),
      );
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: grad),
          child: Column(children: [
            const Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('⚡', style: TextStyle(fontSize: 56)),
                  Text('Instamart Mini', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                  Text('Groceries in 10 minutes', style: TextStyle(color: Colors.white70)),
                ]),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Sign In', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const Text('Welcome back! Ready to shop?', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 20),
                TextField(decoration: fieldDeco('Email address', Icons.mail_outline)),
                const SizedBox(height: 12),
                TextField(obscureText: true, decoration: fieldDeco('Password', Icons.lock_outline)),
                const SizedBox(height: 20),
                GradButton('Sign In  →', () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()))),
              ]),
            ),
          ]),
        ),
      );
}

Widget sectionTitle(String t) =>
    Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 8), child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)));

Widget banner(String text, Color a, Color b) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(20),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(gradient: LinearGradient(colors: [a, b]), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
    );

// Own State so the carousel keeps its page when the cart changes.
class Banners extends StatefulWidget {
  const Banners({super.key});
  @override
  State<Banners> createState() => _BannersState();
}

class _BannersState extends State<Banners> {
  final c = PageController(viewportFraction: .92);
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 130,
        child: PageView(controller: c, children: [
          banner('Fresh fruits\nat your door 🍎', const Color(0xFF43A047), const Color(0xFF9CCC65)),
          banner('Dairy essentials\nin 10 minutes 🥛', const Color(0xFF1E88E5), const Color(0xFF64B5F6)),
          banner('Snack time! 🍪\nCrunchy picks', const Color(0xFF8E24AA), const Color(0xFFBA68C8)),
        ]),
      );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Widget _grid(List<Product> ps, {bool inList = false}) => GridView.builder(
        shrinkWrap: inList,
        physics: inList ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 215),
        itemCount: ps.length,
        itemBuilder: (_, i) => ProductCard(ps[i]),
      );

  Widget _home() {
    final best = (store.products.where((p) => p.stock > 0).toList()..sort((a, b) => b.stock.compareTo(a.stock))).take(6).toList();
    return ListView(padding: EdgeInsets.zero, children: [
      const SizedBox(height: 12),
      const Banners(),
      sectionTitle('Shop by category'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          for (final c in categories.skip(1))
            Expanded(
              child: GestureDetector(
                onTap: () => store.setCat(c),
                child: Column(children: [
                  Container(
                      height: 64,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(18)),
                      child: Text(catEmoji[c]!, style: const TextStyle(fontSize: 30))),
                  const SizedBox(height: 6),
                  Text(c, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]),
      ),
      sectionTitle('Bestsellers'),
      SizedBox(
        height: 215,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14), children: [
          for (final p in best) Container(width: 165, margin: const EdgeInsets.only(right: 12), child: ProductCard(p)),
        ]),
      ),
      sectionTitle('All products'),
      _grid(store.products, inList: true),
    ]);
  }

  Widget _browse(List<Product> ps) => Column(children: [
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), children: [
            for (final c in categories)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${catEmoji[c]} $c'),
                  selected: store.cat == c,
                  showCheckmark: false,
                  selectedColor: orange,
                  backgroundColor: Colors.white,
                  side: BorderSide.none,
                  labelStyle: TextStyle(fontWeight: FontWeight.w600, color: store.cat == c ? Colors.white : Colors.black87),
                  onSelected: (_) => store.setCat(c),
                ),
              ),
          ]),
        ),
        Expanded(child: ps.isEmpty ? const Center(child: Text('No products found')) : _grid(ps)),
      ]);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final browsing = store.cat != 'All' || store.query.isNotEmpty;
          return Scaffold(
            bottomNavigationBar: NavigationBar(
              selectedIndex: 0,
              onDestinationSelected: (i) {
                if (i == 1) go(context, const TrackPage());
                if (i == 2) go(context, const CartPage());
              },
              destinations: [
                const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
                NavigationDestination(
                    icon: Badge(isLabelVisible: store.cartCount > 0, label: Text('${store.cartCount}'), child: const Icon(Icons.shopping_bag_outlined)),
                    label: 'Cart'),
              ],
            ),
            body: Stack(children: [
              Column(children: [
                Container(
                  padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 16),
                  decoration: const BoxDecoration(gradient: grad, borderRadius: BorderRadius.vertical(bottom: Radius.circular(28))),
                  child: Column(children: [
                    Row(children: [
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Delivery in 10 minutes ⚡', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          Text('Deliver to Home ▾', style: TextStyle(color: Colors.white70)),
                        ]),
                      ),
                      const CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.person_outline, color: Colors.white)),
                    ]),
                    const SizedBox(height: 12),
                    TextField(onChanged: store.setQuery, decoration: fieldDeco('Search "milk"', Icons.search, fill: Colors.white)),
                  ]),
                ),
                Expanded(child: browsing ? _browse(store.visible) : _home()),
              ]),
              if (store.cartCount > 0)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: GradButton('${store.cartCount} items · ₹${store.cartTotal.toInt()}      View cart  →', () => go(context, const CartPage())),
                ),
            ]),
          );
        },
      );
}

class QtyControl extends StatelessWidget {
  final Product p;
  const QtyControl(this.p, {super.key});
  @override
  Widget build(BuildContext context) {
    final n = store.cart[p.id] ?? 0;
    if (p.stock == 0) return const Text('Out of stock', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600));
    if (n == 0) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
            foregroundColor: orange,
            side: const BorderSide(color: orange),
            minimumSize: const Size(60, 34),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        onPressed: () => store.change(p, 1),
        child: const Text('ADD', style: TextStyle(fontWeight: FontWeight.w800)),
      );
    }
    Widget btn(IconData i, VoidCallback? f) =>
        InkWell(onTap: f, child: Padding(padding: const EdgeInsets.all(7), child: Icon(i, size: 18, color: f == null ? Colors.white54 : Colors.white)));
    return Container(
      decoration: BoxDecoration(color: orange, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove, () => store.change(p, -1)),
        Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        btn(Icons.add, n < p.stock ? () => store.change(p, 1) : null),
      ]),
    );
  }
}

class ProductCard extends StatelessWidget {
  final Product p;
  const ProductCard(this.p, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: cardBox(20),
        child: Column(children: [
          Expanded(
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
              child: Opacity(opacity: p.stock == 0 ? .35 : 1, child: Text(p.emoji, style: const TextStyle(fontSize: 48))),
            ),
          ),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('₹${p.price.toInt()}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              if (p.stock > 0 && p.stock <= 5) Text('Only ${p.stock} left', style: const TextStyle(color: Colors.red, fontSize: 11)),
            ]),
            QtyControl(p),
          ]),
        ]),
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
          final total = '₹${store.cartTotal.toInt()}';
          return Scaffold(
            appBar: AppBar(
                title: const Text('Your cart', style: TextStyle(fontWeight: FontWeight.w700)),
                backgroundColor: bg,
                surfaceTintColor: Colors.transparent),
            body: lines.isEmpty
                ? const Center(child: Text('🛒\nYour cart is empty', textAlign: TextAlign.center, style: TextStyle(fontSize: 22)))
                : Column(children: [
                    Expanded(
                      child: ListView(padding: const EdgeInsets.all(16), children: [
                        for (final p in lines)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: cardBox(),
                            child: Row(children: [
                              Container(
                                  width: 52,
                                  height: 52,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
                                  child: Text(p.emoji, style: const TextStyle(fontSize: 28))),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text('₹${p.price.toInt()} × ${store.cart[p.id]}', style: const TextStyle(color: Colors.black54)),
                                ]),
                              ),
                              QtyControl(p),
                            ]),
                          ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: cardBox(),
                          child: Column(children: [
                            if (store.deliveryFee > 0)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text('Add ₹${(99 - store.cartTotal).toInt()} more for free delivery 🛵',
                                      style: const TextStyle(color: orange, fontWeight: FontWeight.w600))),
                            billRow('Item total', total),
                            billRow('Delivery fee', store.deliveryFee == 0 ? 'FREE' : '₹${store.deliveryFee.toInt()}',
                                color: store.deliveryFee == 0 ? Colors.green : null),
                            billRow('Handling fee', '₹${store.handlingFee.toInt()}'),
                            const Divider(),
                            billRow('To pay', '₹${store.payable.toInt()}', bold: true),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                            controller: addr,
                            onChanged: (_) => setState(() {}),
                            decoration: fieldDeco('Delivery address', Icons.location_on_outlined, fill: Colors.white)),
                        const SizedBox(height: 6),
                        const Text('Payment: Cash on delivery (mock)', style: TextStyle(color: Colors.black54, fontSize: 12)),
                        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: GradButton('Place order', addr.text.trim().isEmpty
                          ? null
                          : () {
                              final bad = store.place();
                              if (bad.isEmpty) {
                                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TrackPage()));
                              } else {
                                setState(() => error = 'Not enough stock: ${bad.join(', ')}');
                              }
                            }),
                    ),
                  ]),
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
          const heads = ['Order confirmed ✅', 'Packing your items 📦', 'On the way 🛵', 'Delivered 🎉'];
          return Scaffold(
            appBar: AppBar(
                title: const Text('Order status'),
                foregroundColor: Colors.white,
                flexibleSpace: Container(decoration: const BoxDecoration(gradient: grad))),
            body: o == null
                ? const Center(child: Text('No orders yet'))
                : ListView(padding: const EdgeInsets.all(20), children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(gradient: grad, borderRadius: BorderRadius.circular(20)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(heads[o.status], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('Order #${o.id} · ₹${o.total.toInt()}', style: const TextStyle(color: Colors.white70)),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    for (var i = 0; i < steps.length; i++)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Column(children: [
                          Icon(i <= o.status ? Icons.check_circle : Icons.radio_button_unchecked, color: i <= o.status ? orange : Colors.grey.shade400),
                          if (i < steps.length - 1) Container(width: 2, height: 36, color: i < o.status ? orange : Colors.grey.shade300),
                        ]),
                        const SizedBox(width: 14),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(steps[i], style: TextStyle(fontSize: 16, fontWeight: i == o.status ? FontWeight.w800 : FontWeight.w400)),
                        ),
                      ]),
                  ]),
          );
        },
      );
