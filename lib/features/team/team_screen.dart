import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import 'invite_member_bottom_sheet.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  late Future<Map<String, dynamic>?> _teamFuture;

  @override
  void initState() {
    super.initState();
    _teamFuture = _loadTeamData();
  }

  Future<Map<String, dynamic>?> _loadTeamData() async {
    final team = await SupabaseService().getTeam();
    if (team == null) return null;
    final members =
        await SupabaseService().getTeamMembers(team['id'] as String);
    return {'team': team, 'members': members};
  }

  void _reload() {
    setState(() {
      _teamFuture = _loadTeamData();
    });
  }

  Future<void> _inviteMember() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const InviteMemberBottomSheet(),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite sent!')),
      );
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Management'),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _teamFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load team: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(
              child: Text('You are not part of a team.'),
            );
          }

          final team = data['team'] as Map<String, dynamic>;
          final members = data['members'] as List<Map<String, dynamic>>;
          final seatLimit = (team['seat_limit'] as int?) ?? 3;
          final activeCount =
              members.where((m) => m['status'] == 'active').length;
          final isOwner = team['owner_id'] == currentUserId;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Seat usage card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.people),
                      const SizedBox(width: 12),
                      Text(
                        'Seats used: $activeCount / $seatLimit',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Members',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              ...members.map((member) {
                final role = member['role'] as String? ?? 'member';
                final status = member['status'] as String? ?? 'active';
                final email = member['email'] as String? ?? '';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(email),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'pending')
                        _Badge(label: 'Pending', color: Colors.orange),
                      const SizedBox(width: 6),
                      _Badge(
                        label: role == 'owner' ? 'Owner' : 'Member',
                        color: role == 'owner' ? Colors.amber : Colors.grey,
                      ),
                    ],
                  ),
                );
              }),
              if (isOwner) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _inviteMember,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Invite Member'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
