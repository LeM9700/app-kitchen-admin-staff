import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/cards/stat_card.dart';
import 'package:app_admin_staff/design_system/components/feedback/app_feedback.dart';
import 'package:app_admin_staff/design_system/components/forms/pill_filter_bar.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/admin_users/data/admin_users_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _adminUsersQueryProvider = StateProvider<AdminUsersQuery>((ref) {
  return const AdminUsersQuery();
});

final _adminUsersSearchProvider = StateProvider<String>((ref) => '');
final _adminUsersAccessFilterProvider = StateProvider<bool>((ref) => false);
final _selectedAdminUserIdProvider = StateProvider<int?>((ref) => null);

class AdminUsersPage extends ConsumerWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(_adminUsersQueryProvider);
    final search = ref.watch(_adminUsersSearchProvider);
    final mustConfigureOnly = ref.watch(_adminUsersAccessFilterProvider);
    final users = ref.watch(adminUsersProvider(query));
    final selectedId = ref.watch(_selectedAdminUserIdProvider);

    return Padding(
      padding: EdgeInsets.all(
        Breakpoints.isMobile(context) ? AppSpacing.md : AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Equipe',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Staff, acces et activite',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showCreateUserDialog(context, ref),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Ajouter un membre'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          users.when(
            data: (page) => _UsersStats(users: page.items),
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.md),
          _UsersFilters(query: query),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: users.when(
              data: (page) {
                final visibleUsers = _filterLocally(
                  page.items,
                  search,
                  mustConfigureOnly: mustConfigureOnly,
                );
                if (visibleUsers.isEmpty) {
                  return const AppFeedback(
                    kind: AppFeedbackKind.noResults,
                    title: 'Aucun membre',
                    message: 'Aucun utilisateur ne correspond aux filtres.',
                  );
                }
                AdminUser? selected;
                for (final user in visibleUsers) {
                  if (user.id == selectedId) {
                    selected = user;
                    break;
                  }
                }
                final activeSelected = selected ?? visibleUsers.first;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final current = ref.read(_selectedAdminUserIdProvider);
                  if (current != activeSelected.id) {
                    ref.read(_selectedAdminUserIdProvider.notifier).state =
                        activeSelected.id;
                  }
                });

                if (Breakpoints.isCompactDesktop(context) ||
                    Breakpoints.isMobile(context)) {
                  return ListView(
                    children: [
                      ...visibleUsers.map(
                        (user) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _UserCard(
                            user: user,
                            selected: user.id == activeSelected.id,
                            onTap: () {
                              ref
                                  .read(_selectedAdminUserIdProvider.notifier)
                                  .state = user.id;
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _UserDetailPanel(user: activeSelected),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 760,
                      child: _UsersTable(
                        users: visibleUsers,
                        selectedId: activeSelected.id,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(child: _UserDetailPanel(user: activeSelected)),
                  ],
                );
              },
              loading: () => const AppFeedback(
                kind: AppFeedbackKind.loading,
                title: 'Chargement des membres',
              ),
              error: (error, stackTrace) => _ErrorPanel(
                error: error,
                onRetry: () => ref.invalidate(adminUsersProvider(query)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersStats extends StatelessWidget {
  const _UsersStats({required this.users});

  final List<AdminUser> users;

  @override
  Widget build(BuildContext context) {
    final active = users.where((user) => user.isActive).length;
    final mustChange = users.where((user) => user.mustChangePassword).length;
    final admins = users
        .where((user) => user.role == 'admin' || user.role == 'super-admin')
        .length;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        AppStatCard(
          label: 'Membres',
          value: users.length.toString(),
          icon: Icons.groups_2_outlined,
          accentColor: AppColors.accent,
        ),
        AppStatCard(
          label: 'Comptes actifs',
          value: active.toString(),
          icon: Icons.check_circle_outline,
          accentColor: AppColors.success,
        ),
        AppStatCard(
          label: 'Premiere connexion',
          value: mustChange.toString(),
          icon: Icons.lock_reset_outlined,
          accentColor: AppColors.warning,
        ),
        AppStatCard(
          label: 'Admins',
          value: admins.toString(),
          icon: Icons.admin_panel_settings_outlined,
          accentColor: AppColors.infoAlt,
        ),
      ],
    );
  }
}

class _UsersFilters extends ConsumerWidget {
  const _UsersFilters({required this.query});

  final AdminUsersQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRole = query.role ?? 'all';
    final selectedStatus = query.isActive == null
        ? 'all'
        : query.isActive == true
            ? 'active'
            : 'inactive';
    final mustConfigureOnly = ref.watch(_adminUsersAccessFilterProvider);

    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: TextField(
              key: const ValueKey('admin-users-search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Recherche',
              ),
              onChanged: (value) {
                ref.read(_adminUsersSearchProvider.notifier).state = value;
              },
            ),
          ),
          PillFilterBar<String>(
            options: const [
              PillFilterOption(value: 'all', label: 'Tous'),
              PillFilterOption(value: 'staff', label: 'Staff'),
              PillFilterOption(value: 'admin', label: 'Admin'),
            ],
            selected: selectedRole,
            onSelected: (value) {
              ref.read(_adminUsersQueryProvider.notifier).state =
                  query.copyWith(
                role: value,
                clearRole: value == 'all',
              );
            },
          ),
          PillFilterBar<String>(
            options: const [
              PillFilterOption(value: 'all', label: 'Tous statuts'),
              PillFilterOption(value: 'active', label: 'Actifs'),
              PillFilterOption(value: 'inactive', label: 'Inactifs'),
            ],
            selected: selectedStatus,
            onSelected: (selected) {
              ref.read(_adminUsersQueryProvider.notifier).state =
                  query.copyWith(
                isActive: selected == 'active'
                    ? true
                    : selected == 'inactive'
                        ? false
                        : null,
                clearIsActive: selected == 'all',
              );
            },
          ),
          FilterChip(
            selected: mustConfigureOnly,
            avatar: const Icon(Icons.lock_reset_outlined),
            label: const Text('Acces a configurer'),
            onSelected: (value) {
              ref.read(_adminUsersAccessFilterProvider.notifier).state = value;
            },
          ),
          OutlinedButton.icon(
            onPressed: () {
              ref.read(_adminUsersQueryProvider.notifier).state =
                  const AdminUsersQuery();
              ref.read(_adminUsersSearchProvider.notifier).state = '';
              ref.read(_adminUsersAccessFilterProvider.notifier).state = false;
            },
            icon: const Icon(Icons.filter_list_outlined),
            label: const Text('Filtrer / Trier'),
          ),
        ],
      ),
    );
  }
}

class _UsersTable extends ConsumerWidget {
  const _UsersTable({
    required this.users,
    required this.selectedId,
  });

  final List<AdminUser> users;
  final int selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        child: DataTable(
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('Membre')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Statut')),
            DataColumn(label: Text('Acces')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final user in users)
              DataRow(
                selected: user.id == selectedId,
                onSelectChanged: (_) {
                  ref.read(_selectedAdminUserIdProvider.notifier).state =
                      user.id;
                },
                cells: [
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.displayName),
                        Text(
                          user.email,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  DataCell(_RoleChip(role: user.role)),
                  DataCell(_AccountStatusChip(user: user)),
                  DataCell(_AccessStatusChip(user: user)),
                  DataCell(_ActionsMenu(user: user)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  final AdminUser user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      backgroundColor:
          selected ? AppColors.infoBg : Theme.of(context).colorScheme.surface,
      borderColor: selected ? AppColors.infoAlt : null,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListTile(
        minVerticalPadding: AppSpacing.sm,
        leading: CircleAvatar(child: Text(_initials(user))),
        title: Text(user.displayName),
        subtitle: Text(user.email),
        trailing: Wrap(
          spacing: AppSpacing.xs,
          children: [
            _RoleChip(role: user.role),
            _AccountStatusChip(user: user),
          ],
        ),
      ),
    );
  }
}

class _UserDetailPanel extends ConsumerWidget {
  const _UserDetailPanel({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final createdAt = DateFormat('dd/MM/yyyy HH:mm').format(user.createdAt);
    final permissions = PermissionSet(
      role: user.role,
      permissions: user.permissions?.toSet(),
    );

    return DsCard(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 24, child: Text(_initials(user))),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(user.email),
                    ],
                  ),
                ),
                _ActionsMenu(user: user),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _RoleChip(role: user.role),
                _AccountStatusChip(user: user),
                _AccessStatusChip(user: user),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Compte & identite',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ReadOnlyField(label: 'Nom complet', value: user.displayName),
            _ReadOnlyField(label: 'E-mail', value: user.email),
            _ReadOnlyField(label: 'Role', value: user.role),
            _ReadOnlyField(
              label: 'Statut',
              value: user.isActive ? 'Actif' : 'Inactif',
            ),
            _ReadOnlyField(label: 'Cree le', value: createdAt),
            _ReadOnlyField(
              label: 'Email verifie',
              value: user.emailVerified ? 'Oui' : 'Non',
            ),
            if (user.mustChangePassword) ...[
              const SizedBox(height: AppSpacing.sm),
              DsCard(
                backgroundColor: AppColors.warningSoftBg,
                borderColor: const Color(0xFFF5CD80),
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(
                      Icons.lock_reset_outlined,
                      color: AppColors.warning,
                    ),
                    Text(
                      'Premiere connexion requise',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const StatusBadge(
                      label: 'must_change_password = true',
                      tone: StatusTone.warning,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Permissions Staff',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (user.role == 'staff' || user.role == 'admin')
                  OutlinedButton.icon(
                    onPressed: () => _showPermissionsDialog(context, ref, user),
                    icon: const Icon(Icons.tune_outlined),
                    label: const Text('Modifier'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Column(
              children: [
                for (final item in _permissionChoices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _PermissionRow(
                      item: item,
                      granted: permissions.can(item.value),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionsMenu extends ConsumerWidget {
  const _ActionsMenu({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_UserAction>(
      tooltip: 'Actions',
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _UserAction.resetPassword,
          child: Text('Mot de passe temporaire'),
        ),
        PopupMenuItem(
          value:
              user.isActive ? _UserAction.deactivate : _UserAction.reactivate,
          child: Text(user.isActive ? 'Desactiver' : 'Reactiver'),
        ),
      ],
      onSelected: (action) => _runUserAction(context, ref, user, action),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: role,
      tone: role == 'admin' || role == 'super-admin'
          ? StatusTone.info
          : StatusTone.neutral,
      icon: Icons.badge_outlined,
      compact: true,
    );
  }
}

class _AccountStatusChip extends StatelessWidget {
  const _AccountStatusChip({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: user.isActive ? 'Actif' : 'Inactif',
      tone: user.isActive ? StatusTone.success : StatusTone.danger,
      icon: user.isActive ? Icons.check_circle_outline : Icons.block_outlined,
      compact: true,
    );
  }
}

class _AccessStatusChip extends StatelessWidget {
  const _AccessStatusChip({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label:
          user.mustChangePassword ? 'Acces a configurer' : 'Acces initialise',
      tone: user.mustChangePassword ? StatusTone.warning : StatusTone.success,
      icon: user.mustChangePassword
          ? Icons.lock_reset_outlined
          : Icons.verified_user_outlined,
      compact: true,
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.adminSurfaceMuted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xxs),
            Text(value, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.item,
    required this.granted,
  });

  final _PermissionChoice item;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.adminSurfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: granted ? AppColors.accent : AppColors.adminSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: granted ? AppColors.accent : AppColors.adminBorder,
              ),
            ),
            child: granted
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: Theme.of(context).textTheme.labelLarge),
                Text(
                  item.value,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.infoAlt,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(_errorMessage(error)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showCreateUserDialog(BuildContext context, WidgetRef ref) async {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final nameController = TextEditingController();
  var role = 'staff';
  final selectedPermissions = <String>{...AppPermission.staffDefaults};

  final result = await showDialog<AdminUserCreateDraft>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Creer un membre'),
            content: SizedBox(
              width: 520,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        key: const ValueKey('create-user-email'),
                        controller: emailController,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          final raw = value?.trim() ?? '';
                          if (!raw.contains('@')) {
                            return 'Email invalide';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController,
                        decoration:
                            const InputDecoration(labelText: 'Nom complet'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(
                            value: 'staff',
                            child: Text('Staff'),
                          ),
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Admin'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            role = value ?? 'staff';
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Permissions',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in _permissionChoices)
                            FilterChip(
                              label: Text(item.label),
                              selected:
                                  selectedPermissions.contains(item.value),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    selectedPermissions.add(item.value);
                                  } else {
                                    selectedPermissions.remove(item.value);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) {
                    return;
                  }
                  Navigator.of(context).pop(
                    AdminUserCreateDraft(
                      email: emailController.text,
                      fullName: nameController.text,
                      role: role,
                      permissions: selectedPermissions.toList()..sort(),
                    ),
                  );
                },
                icon: const Icon(Icons.check),
                label: const Text('Creer'),
              ),
            ],
          );
        },
      );
    },
  );

  emailController.dispose();
  nameController.dispose();

  if (result == null || !context.mounted) {
    return;
  }
  try {
    final created =
        await ref.read(adminUsersRepositoryProvider).createUser(result);
    ref.invalidate(adminUsersProvider);
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Membre cree'),
        content: SelectableText(
          'Mot de passe temporaire pour ${created.email}\n\n'
          '${created.temporaryPassword}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  } catch (error) {
    if (context.mounted) {
      _showError(context, error);
    }
  }
}

Future<void> _showPermissionsDialog(
  BuildContext context,
  WidgetRef ref,
  AdminUser user,
) async {
  final selected = <String>{
    if (user.permissions == null) ...AppPermission.staffDefaults,
    ...?user.permissions,
  };
  final result = await showDialog<List<String>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Acces de ${user.displayName}'),
            content: SizedBox(
              width: 520,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in _permissionChoices)
                    FilterChip(
                      label: Text(item.label),
                      selected: selected.contains(item.value),
                      onSelected: (value) {
                        setState(() {
                          if (value) {
                            selected.add(item.value);
                          } else {
                            selected.remove(item.value);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(selected.toList()..sort());
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Enregistrer'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == null) {
    return;
  }
  try {
    await ref.read(adminUsersRepositoryProvider).updatePermissions(
          user.id,
          result,
        );
    ref.invalidate(adminUsersProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissions mises a jour')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      _showError(context, error);
    }
  }
}

Future<void> _runUserAction(
  BuildContext context,
  WidgetRef ref,
  AdminUser user,
  _UserAction action,
) async {
  final repository = ref.read(adminUsersRepositoryProvider);
  try {
    switch (action) {
      case _UserAction.resetPassword:
        final temporaryPassword = await repository.resetPassword(user.id);
        if (!context.mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Mot de passe temporaire'),
            content: SelectableText(temporaryPassword),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ],
          ),
        );
      case _UserAction.deactivate:
        final confirmed = await _confirm(
          context,
          title: 'Desactiver le compte',
          content: 'Le compte sera bloque et ses sessions seront revoquees.',
        );
        if (!confirmed) {
          return;
        }
        await repository.deactivateUser(user.id);
      case _UserAction.reactivate:
        await repository.reactivateUser(user.id);
    }
    ref.invalidate(adminUsersProvider);
  } catch (error) {
    if (context.mounted) {
      _showError(context, error);
    }
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ) ??
      false;
}

void _showError(BuildContext context, Object error) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_errorMessage(error))),
  );
}

String _errorMessage(Object error) {
  if (error is AppException) {
    if (error.statusCode == 403) {
      return 'Acces refuse';
    }
    if (error.statusCode == 409) {
      return error.message;
    }
    if (error.statusCode == 422) {
      return error.field == null
          ? error.message
          : '${error.field}: ${error.message}';
    }
    return error.message;
  }
  return error.toString();
}

List<AdminUser> _filterLocally(
  List<AdminUser> users,
  String? search, {
  bool mustConfigureOnly = false,
}) {
  final term = search?.trim().toLowerCase();
  return users.where((user) {
    if (mustConfigureOnly && !user.mustChangePassword) {
      return false;
    }
    if (term == null || term.isEmpty) {
      return true;
    }
    return user.email.toLowerCase().contains(term) ||
        user.displayName.toLowerCase().contains(term);
  }).toList();
}

String _initials(AdminUser user) {
  final source = user.displayName.trim();
  if (source.isEmpty) {
    return '?';
  }
  final parts = source.split(RegExp(r'\s+'));
  if (parts.length == 1) {
    return parts.first.characters.first.toUpperCase();
  }
  return '${parts.first.characters.first}${parts.last.characters.first}'
      .toUpperCase();
}

enum _UserAction { resetPassword, deactivate, reactivate }

class _PermissionChoice {
  const _PermissionChoice(this.value, this.label);

  final String value;
  final String label;
}

const _permissionChoices = [
  _PermissionChoice(AppPermission.ordersRead, 'Commandes lecture'),
  _PermissionChoice(AppPermission.ordersManual, 'Commandes manuelles'),
  _PermissionChoice(AppPermission.ordersWrite, 'Commandes edition'),
  _PermissionChoice(AppPermission.ordersPreparation, 'Cuisine'),
  _PermissionChoice(AppPermission.paymentsRead, 'Paiements lecture'),
  _PermissionChoice(AppPermission.paymentsTerminal, 'Terminal'),
  _PermissionChoice(AppPermission.stockRead, 'Stock lecture'),
  _PermissionChoice(AppPermission.stockWrite, 'Stock edition'),
  _PermissionChoice(AppPermission.stockAdjustmentCreate, 'Ajustements stock'),
  _PermissionChoice(AppPermission.catalogRead, 'Catalogue lecture'),
  _PermissionChoice(AppPermission.catalogWrite, 'Catalogue edition'),
  _PermissionChoice(AppPermission.catalogAvailability, 'Disponibilites'),
  _PermissionChoice(AppPermission.deliveryRead, 'Livraison'),
  _PermissionChoice(AppPermission.promotionsRead, 'Promotions'),
  _PermissionChoice(AppPermission.loyaltyRead, 'Fidelite'),
  _PermissionChoice(AppPermission.printRead, 'Impression'),
];
