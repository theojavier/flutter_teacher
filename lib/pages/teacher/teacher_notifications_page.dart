import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/helpers/AppTheme.dart';
import '/widgets/teacher_notification_bubble.dart';
const Color _dashboardBlue = Color(0xFF153CFF);
class TeacherNotificationsPage extends StatefulWidget {
  const TeacherNotificationsPage({super.key});

  @override
  State<TeacherNotificationsPage> createState() =>
      _TeacherNotificationsPageState();
}

class _TeacherNotificationsPageState extends State<TeacherNotificationsPage> {
  static const int _pageSize = 10;

  late final Stream<QuerySnapshot<Map<String, dynamic>>>? _notifications;
  bool _unreadOnly = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _notifications = teacherNotificationsRef()
        ?.orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final padding = compact ? 16.0 : 24.0;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FOTS / NOTIFICATIONS',
               style: TextStyle(
            color: _dashboardBlue,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          )),
              const SizedBox(height: 12),
              Text(
                'Notifications.',
                style: AppTheme.display(compact ? 32 : 34, ls: -0.06),
              ),
              const SizedBox(height: 6),
              const Text(
                'Admin decisions on the exams you submitted for review',
                style: TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: AppTheme.cardDecoration(),
                  child: _notifications == null
                      ? _centered(
                          AppTheme.emptyCardBlue(
                            Icons.person_off_outlined,
                            'Sign in to see your notifications.',
                          ),
                        )
                      : _notificationList(_notifications),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notificationList(Stream<QuerySnapshot<Map<String, dynamic>>> stream) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _centered(
            AppTheme.emptyCardBlue(
              Icons.error_outline,
              'Could not load notifications. Check your connection and try again.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(48),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),
          );
        }

        final all = snapshot.data!.docs
            .map(TeacherNotification.fromDoc)
            .toList();
        final unreadCount = all
            .where((notification) => !notification.read)
            .length;
        final visible = _unreadOnly
            ? all.where((notification) => !notification.read).toList()
            : all;
        final pageCount = (visible.length / _pageSize).ceil();
        final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1).toInt();
        final items = visible.skip(page * _pageSize).take(_pageSize).toList();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
              total: all.length,
              unread: unreadCount,
              onMarkAllRead: unreadCount == 0
                  ? null
                  : () => markAllTeacherNotificationsRead(),
            ),
            if (items.isEmpty)
              _centered(
                AppTheme.emptyCardBlue(
                  _unreadOnly
                      ? Icons.done_all
                      : Icons.notifications_off_outlined,
                  
                  _unreadOnly
                      ? 'You are all caught up.'
                      : 'No notifications yet. Admin decisions on your exams will show up here.',
                ),
              )
            else
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppTheme.line),
                TeacherNotificationTile(
                  n: items[i],
                  noteLines: 4,
                  showMessage: true,
                  onTap: () =>
                      openTeacherNotification(GoRouter.of(context), items[i]),
                ),
              ],
            if (pageCount > 1) _pager(page, pageCount),
          ],
        );
      },
    );
  }

  Widget _header({
    required int total,
    required int unread,
    required VoidCallback? onMarkAllRead,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: AppTheme.header,
        border: Border(bottom: BorderSide(color: AppTheme.line)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 14,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Inbox',
                style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$unread unread · $total total',
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterButton(
                'All',
                Icons.view_list_outlined,
                !_unreadOnly,
                () => setState(() {
                  _unreadOnly = false;
                  _page = 0;
                }),
              ),
              _filterButton(
                'Unread',
                Icons.mark_email_unread_outlined,
                _unreadOnly,
                () => setState(() {
                  _unreadOnly = true;
                  _page = 0;
                }),
              ),
              OutlinedButton.icon(
                onPressed: onMarkAllRead,
                icon: const Icon(Icons.done_all, size: 17),
                label: const Text('Mark all as read'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.text,
                  backgroundColor: AppTheme.header,
                  side: const BorderSide(color: AppTheme.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterButton(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onPressed,
  ) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : AppTheme.text,
        backgroundColor: selected ? const Color.fromARGB(255, 98, 45, 223) : AppTheme.header,
        side: BorderSide(color: selected ? const Color.fromARGB(255, 48, 45, 223) : AppTheme.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _pager(int page, int pageCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left),
            color: AppTheme.text,
            onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
          ),
          Text(
            'Page ${page + 1} of $pageCount',
            style: const TextStyle(color: AppTheme.mutedText, fontSize: 12.5),
          ),
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right),
            color: AppTheme.text,
            onPressed: page < pageCount - 1
                ? () => setState(() => _page = page + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _centered(Widget child) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: child,
      ),
    ),
  );
}
