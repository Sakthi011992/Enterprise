import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/ui/ui.dart';
import '../data/guest_models.dart';
import '../data/guest_requests_providers.dart';
import '../data/guest_requests_repository.dart';
import 'edit_confirm_sheet.dart';
import 'reject_dialog.dart';

/// `/service/guest-orders`: service requests on top, then each pending guest
/// round with Reject, Claim and Confirm. Design: "Waiter · Guest orders".
class GuestOrdersScreen extends ConsumerStatefulWidget {
  const GuestOrdersScreen({super.key});

  @override
  ConsumerState<GuestOrdersScreen> createState() => _GuestOrdersScreenState();
}

class _GuestOrdersScreenState extends ConsumerState<GuestOrdersScreen> {
  Timer? _ticker;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    // Re-render so the "1 min" ages stay current.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  GuestRequestsRepository get _repo => ref.read(guestRequestsRepositoryProvider);

  void _refresh() {
    ref.invalidate(pendingGuestRequestsProvider);
    ref.invalidate(serviceRequestsProvider);
  }

  Future<void> _run(String id, Future<void> Function() call, {String? success}) async {
    setState(() => _busy.add(id));
    try {
      await call();
      if (mounted && success != null) showAppToast(context, success);
    } catch (e) {
      if (mounted) showAppToast(context, ApiError.from(e).message);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
      _refresh();
    }
  }

  Future<void> _claim(GuestRequest r) => _run(r.id, () => _repo.claim(r.id));

  Future<void> _reject(GuestRequest r) async {
    final reason = await showRejectReasonDialog(context, request: r);
    if (reason == null) return;
    await _run(r.id, () => _repo.reject(r.id, reason: reason),
        success: 'Round rejected. ${r.guestName} sees the reason.');
  }

  Future<void> _confirm(GuestRequest r) async {
    final result = await showEditConfirmSheet(context, request: r);
    if (result == null || !mounted) return;
    switch (result) {
      case EditConfirmRejected():
        await _reject(r);
      case EditConfirmConfirmed(:final items, :final edited):
        await _run(r.id, () => _repo.confirm(r.id, items: edited ? items : null),
            success: '${r.tableName} sent to the kitchen and bar.');
    }
  }

  Future<void> _ack(ServiceRequest s) => _run(s.id, () => _repo.acknowledge(s.id));
  Future<void> _done(ServiceRequest s) => _run(s.id, () => _repo.done(s.id));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    ref.watch(guestLiveProvider);
    final canView = can(ref, Perm.guestsOrdersConfirm, AccessLevel.view);
    final canAct = can(ref, Perm.guestsOrdersConfirm, AccessLevel.edit);
    final canService = can(ref, Perm.salesOrdersTake, AccessLevel.edit);
    final me = ref.watch(sessionProvider.select((s) => s.session?.user.id));
    final outlet = ref.watch(sessionProvider.select((s) => s.session?.outlet.name));
    final rounds = ref.watch(pendingGuestRequestsProvider);
    final service = ref.watch(serviceRequestsProvider).valueOrNull ?? const <ServiceRequest>[];

    return DensityScope(
      density: AppDensity.pos,
      child: Scaffold(
        body: SafeArea(
          child: !canView
              ? const EmptyState(title: "You can't see guest orders on this device.")
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(t.spacing.md, t.spacing.md, t.spacing.md, 0),
                      child: PageHeader(
                        title: 'Guest orders',
                        breadcrumb: outlet ?? 'Sales',
                        actions: [
                          AppIconButton(icon: Icons.refresh, tooltip: 'Refresh', onPressed: _refresh),
                        ],
                      ),
                    ),
                    if (service.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(t.spacing.md, t.spacing.sm, t.spacing.md, 0),
                        child: ServiceRequestStrip(
                          requests: service,
                          busy: _busy,
                          enabled: canService,
                          onAck: _ack,
                          onDone: _done,
                        ),
                      ),
                    Expanded(
                      child: rounds.when(
                        skipLoadingOnReload: true,
                        loading: () => const DelayedSkeleton(child: SkeletonList()),
                        error: (e, _) => ErrorState(message: ApiError.from(e).message, onRetry: _refresh),
                        data: (list) {
                          if (list.isEmpty) {
                            return const EmptyState(
                              title: 'No guest orders waiting',
                              message: 'New rounds from table QR codes appear here as guests place them.',
                              icon: Icons.qr_code_2,
                            );
                          }
                          return LayoutBuilder(builder: (context, c) {
                            final width = c.maxWidth >= 600 ? 360.0 : c.maxWidth - t.spacing.md * 2;
                            return SingleChildScrollView(
                              padding: EdgeInsets.all(t.spacing.md),
                              child: Wrap(
                                spacing: t.spacing.md,
                                runSpacing: t.spacing.md,
                                children: [
                                  for (final r in list)
                                    SizedBox(
                                      width: width,
                                      child: GuestRoundCard(
                                        request: r,
                                        currentUserId: me,
                                        busy: _busy.contains(r.id),
                                        canAct: canAct,
                                        onClaim: () => _claim(r),
                                        onReject: () => _reject(r),
                                        onConfirm: () => _confirm(r),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// "R2 · Bill please [Ack]" chips. After Ack the button turns into Done.
class ServiceRequestStrip extends StatelessWidget {
  const ServiceRequestStrip({
    super.key,
    required this.requests,
    required this.onAck,
    required this.onDone,
    this.busy = const {},
    this.enabled = true,
  });

  final List<ServiceRequest> requests;
  final Set<String> busy;
  final bool enabled;
  final ValueChanged<ServiceRequest> onAck;
  final ValueChanged<ServiceRequest> onDone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: t.spacing.sm,
      runSpacing: t.spacing.sm,
      children: [
        for (final s in requests)
          Container(
            key: ValueKey('service-${s.id}'),
            padding: EdgeInsets.fromLTRB(t.spacing.sm + 4, t.spacing.xs, t.spacing.xs, t.spacing.xs),
            decoration: BoxDecoration(
              color: s.isBill ? ext.warningSubtle : ext.accentSubtle,
              borderRadius: BorderRadius.circular(t.radius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.tableName,
                    style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: s.isBill ? ext.onWarningSubtle : ext.onAccentSubtle)),
                SizedBox(width: t.spacing.sm),
                Text(ServiceRequestTypes.label(s.type),
                    style: text.bodyMedium?.copyWith(
                        color: s.isBill ? ext.onWarningSubtle : ext.onAccentSubtle)),
                SizedBox(width: t.spacing.sm),
                AppButton(
                  label: s.isAcknowledged ? 'Done' : 'Ack',
                  size: AppControlSize.sm,
                  loading: busy.contains(s.id),
                  onPressed: !enabled ? null : () => s.isAcknowledged ? onDone(s) : onAck(s),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One pending round: table, guest, masked mobile, lines, total, age and
/// actions. Claimed by someone else shows "Ravi is on it" instead.
class GuestRoundCard extends StatelessWidget {
  const GuestRoundCard({
    super.key,
    required this.request,
    required this.currentUserId,
    required this.onClaim,
    required this.onReject,
    required this.onConfirm,
    this.busy = false,
    this.canAct = true,
    this.now,
  });

  final GuestRequest request;
  final String? currentUserId;
  final bool busy;
  final bool canAct;
  final DateTime? now;
  final VoidCallback onClaim;
  final VoidCallback onReject;
  final VoidCallback onConfirm;

  bool get _claimedByOther =>
      request.claimedById != null && request.claimedById != currentUserId;
  bool get _claimedByMe => request.claimedById != null && request.claimedById == currentUserId;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final text = Theme.of(context).textTheme;
    final r = request;
    final age = (now ?? DateTime.now()).difference(r.createdAt);
    final fresh = age.inMinutes < 2;

    return Container(
      key: ValueKey('round-${r.id}'),
      padding: EdgeInsets.all(t.spacing.md),
      decoration: BoxDecoration(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.lg),
        border: Border.all(color: t.color.border.subtle, width: t.borderWidth.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: t.spacing.xs),
                decoration: BoxDecoration(
                  color: t.color.background.accent,
                  borderRadius: BorderRadius.circular(t.radius.sm),
                ),
                child: Text(r.tableName,
                    style: text.titleSmall?.copyWith(
                        color: t.color.content.onAccent, fontWeight: FontWeight.w700)),
              ),
              SizedBox(width: t.spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.guestName, style: text.titleSmall, overflow: TextOverflow.ellipsis),
                    if (r.phoneMasked.isNotEmpty)
                      Text(r.phoneMasked,
                          style: text.bodySmall?.copyWith(color: t.color.content.secondary)),
                  ],
                ),
              ),
              Text(
                ageText(age),
                style: text.labelLarge?.copyWith(
                  color: fresh ? t.color.background.accent : t.color.content.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: t.spacing.sm),
          for (final l in r.lines)
            Padding(
              padding: EdgeInsets.symmetric(vertical: t.spacing.xs / 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 32,
                    child: Text('${l.quantity}×',
                        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(child: Text(l.title, style: text.bodyMedium)),
                  Text(formatInr(l.lineTotal), style: text.bodyMedium),
                ],
              ),
            ),
          SizedBox(height: t.spacing.sm),
          if (_claimedByOther)
            Row(
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: ext.accentSubtle,
                  foregroundColor: ext.onAccentSubtle,
                  child: Text(
                    (r.claimedByName ?? '?').substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(width: t.spacing.sm),
                Text('${r.claimedByName ?? 'Someone'} is on it',
                    style: text.bodyMedium?.copyWith(color: t.color.content.secondary)),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Reject',
                    size: AppControlSize.sm,
                    onPressed: canAct && !busy ? onReject : null,
                  ),
                ),
                if (!_claimedByMe) ...[
                  SizedBox(width: t.spacing.sm),
                  Expanded(
                    child: AppButton(
                      label: 'Claim',
                      size: AppControlSize.sm,
                      onPressed: canAct && !busy ? onClaim : null,
                    ),
                  ),
                ],
                SizedBox(width: t.spacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'Confirm',
                    size: AppControlSize.sm,
                    variant: AppButtonVariant.primary,
                    loading: busy,
                    onPressed: canAct && !busy ? onConfirm : null,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
