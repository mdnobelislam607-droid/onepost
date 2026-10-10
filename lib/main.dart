import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const backendUrl = String.fromEnvironment('BACKEND_URL');

const platformsList = ['youtube', 'facebook', 'instagram', 'tiktok'];
const platformsLive = {'youtube', 'facebook'};

SupabaseClient get db => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const OnePostApp());
}

class OnePostApp extends StatelessWidget {
  const OnePostApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OnePost',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF5B5BF0), useMaterial3: true),
        home: StreamBuilder<AuthState>(
          stream: db.auth.onAuthStateChange,
          builder: (_, __) => db.auth.currentSession == null ? const LoginPage() : const HomePage(),
        ),
      );
}

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), pass = TextEditingController();
  bool busy = false;

  Future<void> go(bool signUp) async {
    setState(() => busy = true);
    try {
      if (signUp) {
        await db.auth.signUp(email: email.text.trim(), password: pass.text);
        if (mounted) toast(context, 'অ্যাকাউন্ট তৈরি হয়েছে। ইমেইল কনফার্ম করুন।');
      } else {
        await db.auth.signInWithPassword(email: email.text.trim(), password: pass.text);
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('OnePost', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
              const Text('একবার আপলোড, সব জায়গায় পাবলিশ'),
              const SizedBox(height: 32),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'ইমেইল')),
              TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'পাসওয়ার্ড')),
              const SizedBox(height: 24),
              FilledButton(onPressed: busy ? null : () => go(false), child: const Text('লগইন')),
              TextButton(onPressed: busy ? null : () => go(true), child: const Text('নতুন অ্যাকাউন্ট')),
            ]),
          ),
        ),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('OnePost'), actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => db.auth.signOut()),
        ]),
        body: [const PublishTab(), const PostsTab(), const AccountsTab()][tab],
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.upload), label: 'পাবলিশ'),
            NavigationDestination(icon: Icon(Icons.list), label: 'স্ট্যাটাস'),
            NavigationDestination(icon: Icon(Icons.link), label: 'অ্যাকাউন্ট'),
          ],
        ),
      );
}

class PublishTab extends StatefulWidget {
  const PublishTab({super.key});
  @override
  State<PublishTab> createState() => _PublishTabState();
}

class _PublishTabState extends State<PublishTab> {
  final title = TextEditingController(), caption = TextEditingController();
  PlatformFile? video;
  final selected = <String>{};
  DateTime? when;
  bool busy = false;

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.video);
    if (r != null) setState(() => video = r.files.single);
  }

  Future<void> pickTime() async {
    final d = await showDatePicker(
        context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t != null) setState(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> submit() async {
    if (video?.path == null || selected.isEmpty) {
      toast(context, 'ভিডিও ও অন্তত একটি প্ল্যাটফর্ম বাছুন');
      return;
    }
    setState(() => busy = true);
    try {
      final uid = db.auth.currentUser!.id;
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_${video!.name}';
      await db.storage.from('videos').upload(path, File(video!.path!));
      final post = await db.from('posts').insert({
        'user_id': uid,
        'title': title.text,
        'caption': caption.text,
        'video_path': path,
        'scheduled_at': (when ?? DateTime.now()).toUtc().toIso8601String(),
      }).select().single();
      await db.from('post_targets').insert([
        for (final p in selected) {'post_id': post['id'], 'platform': p, 'status': 'queued'}
      ]);
      if (mounted) {
        toast(context, 'কিউতে যোগ হয়েছে');
        setState(() {
          video = null;
          selected.clear();
          when = null;
          title.clear();
          caption.clear();
        });
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        OutlinedButton.icon(
            onPressed: pick,
            icon: const Icon(Icons.video_file),
            label: Text(video?.name ?? 'ভিডিও বাছুন')),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'টাইটেল')),
        TextField(controller: caption, maxLines: 3, decoration: const InputDecoration(labelText: 'ক্যাপশন')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final p in platformsList)
            FilterChip(
              label: Text(platformsLive.contains(p) ? p : '$p (শীঘ্রই)'),
              selected: selected.contains(p),
              onSelected: platformsLive.contains(p)
                  ? (v) => setState(() => v ? selected.add(p) : selected.remove(p))
                  : null,
            ),
        ]),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text(when == null ? 'এখনই পাবলিশ' : DateFormat('dd MMM, hh:mm a').format(when!)),
          trailing: TextButton(onPressed: pickTime, child: const Text('শিডিউল')),
        ),
        FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'আপলোড হচ্ছে…' : 'পাবলিশ করুন')),
      ]);
}

class PostsTab extends StatefulWidget {
  const PostsTab({super.key});
  @override
  State<PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<PostsTab> {
  Future<List<dynamic>> load() =>
      db.from('post_targets').select('*, posts(title)').order('created_at', ascending: false).limit(50);

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: FutureBuilder<List<dynamic>>(
          future: load(),
          builder: (_, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final rows = s.data!;
            if (rows.isEmpty) return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('কোনো পোস্ট নেই'))]);
            return ListView(children: [
              for (final r in rows)
                ListTile(
                  title: Text('${r['posts']?['title'] ?? ''} • ${r['platform']}'),
                  subtitle: Text('${r['status']}${r['error'] != null ? '\n${r['error']}' : ''}'),
                  trailing: r['status'] == 'failed'
                      ? IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () async {
                            await db.from('post_targets').update({'status': 'queued', 'error': null}).eq('id', r['id']);
                            setState(() {});
                          })
                      : null,
                ),
            ]);
          },
        ),
      );
}

class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key});
  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  Future<List<dynamic>> load() => db.from('connected_accounts').select('id, platform, display_name');

  Future<void> connect(String p) async {
    final uid = db.auth.currentUser!.id;
    await launchUrl(Uri.parse('$backendUrl/oauth/$p/start?user=$uid'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: load(),
        builder: (_, s) {
          final rows = s.data ?? [];
          return ListView(children: [
            for (final p in platformsLive)
              ListTile(
                title: Text(p),
                subtitle: Text(rows.where((r) => r['platform'] == p).map((r) => r['display_name']).join(', ')),
                trailing: TextButton(onPressed: () => connect(p), child: const Text('কানেক্ট')),
              ),
            for (final r in rows)
              ListTile(
                title: Text('${r['platform']}: ${r['display_name']}'),
                trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      await db.from('connected_accounts').delete().eq('id', r['id']);
                      setState(() {});
                    }),
              ),
          ]);
        },
      );
}
