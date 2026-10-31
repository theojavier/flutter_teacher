// lib/widgets/teacher_notification_bubble.dart
//
// Teacher notification bell + dropdown bubble (latest 5) + shared helpers
// used by the "all notifications" page.
//
// Badge rules:
//   * any unread "changes requested"  -> red circle WITH a number
//   * only unread "approved"          -> red dot, NO number
//   * nothing unread                  -> no badge
//
// The bubble is an overlay, not a route, so opening it does not rebuild the
// current page or create another fullscreen modal surface.
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '/helpers/AppTheme.dart';

const String kNotifApproved = 'exam_approved';
const String kNotifChanges = 'exam_changes_requested';
const int kBubbleLimit = 5;

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class TeacherNotification {
  final String id;
  final String type;
  final String examId;
  final String subject;
  final String title;
  final String message;
  final String note;
  final bool read;
  final DateTime? createdAt;

  const TeacherNotification({
    required this.id,
    required this.type,
    required this.examId,
    required this.subject,
    required this.title,
    required this.message,
    required this.note,
    required this.read,
    required this.createdAt,
  });

  bool get isChangesRequested => type == kNotifChanges;

  factory TeacherNotification.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? <String, dynamic>{};
    final type = (d['type'] ?? '').toString();
    final ts = d['createdAt'];
    final title = (d['title'] ?? '').toString();
    return TeacherNotification(
      id: doc.id,
      type: type,
      examId: (d['examId'] ?? '').toString(),
      subject: (d['subject'] ?? 'Untitled exam').toString(),
      title: title.isNotEmpty
          ? title
          : (type == kNotifChanges ? 'Changes requested' : 'Exam approved'),
      message: (d['message'] ?? '').toString(),
      note: (d['note'] ?? '').toString().trim(),
      read: d['read'] == true,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------
CollectionReference<Map<String, dynamic>>? teacherNotificationsRef() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('notifications');
}

Future<void> markTeacherNotificationRead(String id) async {
  try {
    await teacherNotificationsRef()?.doc(id).update({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('Could not mark notification $id as read: $e');
  }
}

Future<void> markTeacherNotificationsRead(Iterable<String> ids) async {
  final ref = teacherNotificationsRef();
  if (ref == null) return;
  final notificationIds = ids.toSet();
  if (notificationIds.isEmpty) return;

  try {
    final batch = FirebaseFirestore.instance.batch();
    for (final id in notificationIds) {
      batch.update(ref.doc(id), {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  } catch (e) {
    debugPrint('Could not mark notifications as read: $e');
  }
}

Future<void> markAllTeacherNotificationsRead() async {
  final ref = teacherNotificationsRef();
  if (ref == null) return;
  try {
    final snap = await ref.where('read', isEqualTo: false).limit(400).get();
    if (snap.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  } catch (e) {
    debugPrint('Could not mark all notifications as read: $e');
  }
}

/// Marks the notification read and opens the exam's review details on the
/// Exams page. `t` is a throwaway value so tapping the same notification
/// twice re-opens the dialog.
void openTeacherNotification(GoRouter router, TeacherNotification n) {
  if (!n.read) unawaited(markTeacherNotificationRead(n.id));
  if (n.examId.isEmpty) return;
  router.go(
    '/teacher-exams?review=${Uri.encodeQueryComponent(n.examId)}'
    '&t=${DateTime.now().millisecondsSinceEpoch}',
  );
}

String teacherNotifTimeAgo(DateTime? t) {
  if (t == null) return '';
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d, yyyy').format(t);
}

// ---------------------------------------------------------------------------
// One notification row (used by the bubble AND the full page)
// ---------------------------------------------------------------------------
class TeacherNotificationTile extends StatelessWidget {
  final TeacherNotification n;
  final VoidCallback onTap;
  final int noteLines;
  final bool showMessage;

  const TeacherNotificationTile({
    super.key,
    required this.n,
    required this.onTap,
    this.noteLines = 2,
    this.showMessage = false,
  });

  @override
  Widget build(BuildContext context) {
    final changes = n.isChangesRequested;
    final color = changes ? AppTheme.error : AppTheme.success;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: n.read ? Colors.transparent : color.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                changes ? Icons.rate_review_outlined : Icons.verified_outlined,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.text,
                            fontSize: 13.5,
                            fontWeight: n.read
                                ? FontWeight.w600
                                : FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!n.read)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    n.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (showMessage && n.message.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      n.message,
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (changes && n.note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    // Row + Expanded fills the width WITHOUT width: infinity
                    // (infinity breaks intrinsic-size measuring).
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(6),
                              border: const Border(
                                left: BorderSide(
                                  color: AppTheme.error,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Text(
                              'Admin note: ${n.note}',
                              maxLines: noteLines,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.text,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    teacherNotifTimeAgo(n.createdAt),
                    style: AppTheme.mono(10, color: AppTheme.mutedText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The bell + bubble
// ---------------------------------------------------------------------------
class TeacherNotificationBubble extends StatefulWidget {
  const TeacherNotificationBubble({super.key});

  @override
  State<TeacherNotificationBubble> createState() =>
      _TeacherNotificationBubbleState();
}

class _TeacherNotificationBubbleState extends State<TeacherNotificationBubble> {
  final _overlayController = OverlayPortalController();
  Query<Map<String, dynamic>>? _latestQuery;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _latest;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _unread;
  QuerySnapshot<Map<String, dynamic>>? _initialLatest;
  List<TeacherNotification> _visibleNotifications = const [];
  bool _isOpen = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final ref = teacherNotificationsRef();
    if (ref != null) {
      _latestQuery = ref
          .orderBy('createdAt', descending: true)
          .limit(kBubbleLimit);
      _latest = _latestQuery!.snapshots();
      _unread = ref.where('read', isEqualTo: false).limit(100).snapshots();
    }
  }

  Future<void> _open() async {
    if (_isOpen || _isLoading || _latestQuery == null || _latest == null) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;

    setState(() => _isLoading = true);
    try {
      final snapshot = await _latestQuery!.get();
      if (!mounted) return;
      setState(() {
        _initialLatest = snapshot;
        _visibleNotifications = const [];
        _isLoading = false;
        _isOpen = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load notifications: $error')),
      );
      return;
    }
    _overlayController.show();
  }

  void _close({String? notificationBeingOpened}) {
    if (!_isOpen) return;
    _overlayController.hide();
    if (mounted) setState(() => _isOpen = false);
    final approvedIds = _visibleNotifications
        .where(
          (notification) =>
              !notification.read &&
              notification.type == kNotifApproved &&
              notification.id != notificationBeingOpened,
        )
        .map((notification) => notification.id)
        .toList();
    _visibleNotifications = const [];
    unawaited(markTeacherNotificationsRead(approvedIds));
  }

  void _openNotification(TeacherNotification notification) {
    _close(notificationBeingOpened: notification.id);
    openTeacherNotification(GoRouter.of(context), notification);
  }

  void _viewAll() {
    _close();
    GoRouter.of(context).go('/teacher-notifications');
  }

  Widget _buildOverlay(BuildContext context) {
    final latest = _latest;
    final unread = _unread;
    final initialLatest = _initialLatest;
    if (latest == null || unread == null || initialLatest == null) {
      return const SizedBox.shrink();
    }

    final screen = MediaQuery.sizeOf(context);
    final width = math.min(380.0, screen.width - 24);
    final anchor = this.context.findRenderObject();
    if (anchor is! RenderBox || !anchor.attached || !anchor.hasSize) {
      return const SizedBox.shrink();
    }
    final anchorOrigin = anchor.localToGlobal(Offset.zero);
    final left = (anchorOrigin.dx + anchor.size.width - width)
        .clamp(12.0, math.max(12.0, screen.width - width - 12))
        .toDouble();
    final top = anchorOrigin.dy + anchor.size.height + 8;
    final maxHeight = math.max(160.0, screen.height - top - 12);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: ColoredBox(color: AppTheme.text.withValues(alpha: 0.015)),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: width,
          child: Material(
            color: AppTheme.card,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTheme.line),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SizedBox(
                width: width,
                child: _BubblePanel(
                  latest: latest,
                  unread: unread,
                  initialLatest: initialLatest,
                  maxListHeight: math.max(80.0, maxHeight - 100),
                  onNotificationTap: _openNotification,
                  onViewAll: _viewAll,
                  onVisibleChanged: (items) => _visibleNotifications = items,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_unread == null || _latest == null) return _bell(0, 0);

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: _buildOverlay,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _unread,
        builder: (context, snap) {
          var changes = 0;
          var approved = 0;
          for (final d in snap.data?.docs ?? const []) {
            final type = d.data()['type'];
            if (type == kNotifChanges) {
              changes++;
            } else if (type == kNotifApproved) {
              approved++;
            }
          }

          return Semantics(
            button: true,
            label: 'Notifications',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _isLoading
                    ? null
                    : _isOpen
                    ? _close
                    : _open,
                child: _bell(changes, approved, loading: _isLoading),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bell(int changes, int approved, {bool loading = false}) {
    final hasNumber = changes > 0;
    final hasDot = !hasNumber && approved > 0;

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.line),
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.notifications_none_outlined,
                    size: 20,
                    color: AppTheme.text,
                  ),
          ),
          if (hasNumber)
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  changes > 9 ? '9+' : '$changes',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            )
          else if (hasDot)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bubble contents (lives inside the dialog route)
// ---------------------------------------------------------------------------
class _BubblePanel extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> latest;
  final Stream<QuerySnapshot<Map<String, dynamic>>> unread;
  final QuerySnapshot<Map<String, dynamic>> initialLatest;
  final double maxListHeight;
  final ValueChanged<TeacherNotification> onNotificationTap;
  final VoidCallback onViewAll;
  final ValueChanged<List<TeacherNotification>> onVisibleChanged;

  const _BubblePanel({
    required this.latest,
    required this.unread,
    required this.initialLatest,
    required this.maxListHeight,
    required this.onNotificationTap,
    required this.onViewAll,
    required this.onVisibleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.line)),
          ),
          child: Row(
            children: [
              const Text(
                'Notifications',
                style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: unread,
                builder: (_, snap) {
                  var changes = 0;
                  var approved = 0;
                  for (final d in snap.data?.docs ?? const []) {
                    final type = d.data()['type'];
                    if (type == kNotifChanges) {
                      changes++;
                    } else if (type == kNotifApproved) {
                      approved++;
                    }
                  }
                  if (changes > 0) {
                    return _pill('$changes to fix', AppTheme.error);
                  }
                  if (approved > 0) {
                    return _pill('New', AppTheme.success);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: latest,
          initialData: initialLatest,
          builder: (_, snap) {
            if (snap.hasError) {
              return _message(
                Icons.error_outline,
                'Could not load notifications',
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              );
            }
            final items = snap.data!.docs
                .map(TeacherNotification.fromDoc)
                .toList();
            onVisibleChanged(items);
            if (items.isEmpty) {
              return _message(
                Icons.notifications_off_outlined,
                'No notifications yet',
              );
            }
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: AppTheme.line),
                      TeacherNotificationTile(
                        n: items[i],
                        noteLines: 2,
                        onTap: () => onNotificationTap(items[i]),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        InkWell(
          onTap: onViewAll,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.line)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'View all notifications',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward, size: 16, color: AppTheme.accent),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );

  Widget _message(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppTheme.mutedText, size: 28),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
        ),
      ],
    ),
  );
}
