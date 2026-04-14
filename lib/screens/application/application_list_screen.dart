import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/application_provider.dart';
import '../../models/application_record.dart';
import '../../config/app_theme.dart';

class ApplicationListScreen extends StatefulWidget {
  const ApplicationListScreen({super.key});

  @override
  State<ApplicationListScreen> createState() => _ApplicationListScreenState();
}

class _ApplicationListScreenState extends State<ApplicationListScreen> {
  String _statusFilter = 'all';

  List<ApplicationRecord> _filterRecords(List<ApplicationRecord> records) {
    return records.where((r) {
      if (_statusFilter != 'all' && r.status != _statusFilter) return false;
      return true;
    }).toList();
  }

  Widget _buildStatusFilter() {
    final items = [
      ('all', '전체'),
      ('saved', '저장됨'),
      ('preparing', '준비 중'),
      ('applied', '신청 완료'),
    ];
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: items.map((e) {
          final selected = _statusFilter == e.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(e.$2),
              selected: selected,
              onSelected: (_) => setState(() => _statusFilter = e.$1),
              selectedColor: AppTheme.primary.withValues(alpha: 0.12),
              labelStyle: TextStyle(
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              ),
              side: BorderSide(color: selected ? AppTheme.primary : AppTheme.divider),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('신청 관리')),
      body: Consumer<ApplicationProvider>(
        builder: (_, provider, __) {
          final records = provider.records;
          final filtered = _filterRecords(records);
          if (records.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('저장된 서비스가 없습니다.',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade400)),
                const SizedBox(height: 8),
                Text('복지 서비스 상세에서 "신청 관리 추가"를 눌러보세요.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
              ]),
            );
          }
          return Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildStatusFilter()),
                        const SizedBox(width: 8),
                        Text(
                          '${filtered.length}/${records.length}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          '조건에 맞는 신청 항목이 없습니다.',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _RecordCard(record: filtered[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final ApplicationRecord record;
  const _RecordCard({required this.record});

  Future<void> _changeStatus(BuildContext context, String status) async {
    if (record.status == status) return;
    record.status = status;
    await context.read<ApplicationProvider>().update(record);
  }

  Future<void> _deleteRecord(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제'),
        content: const Text('신청 관리 항목을 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<ApplicationProvider>().remove(record.serviceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusIcon) = _statusStyle(record.status);
    final categoryColor = AppTheme.categoryColors[record.category] ?? AppTheme.primary;
    final hasChecklist = record.docs.isNotEmpty;

    return GestureDetector(
      onTap: () => context.push('/application/${record.serviceId}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, size: 12, color: statusColor),
                const SizedBox(width: 4),
                Text(record.statusLabel,
                    style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w700)),
              ]),
            ),
            const Spacer(),
            Text(_formatDate(record.savedAt),
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            PopupMenuButton<String>(
              tooltip: '관리',
              onSelected: (v) {
                if (v == 'saved' || v == 'preparing' || v == 'applied') {
                  _changeStatus(context, v);
                } else if (v == 'delete') {
                  _deleteRecord(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'saved', child: Text('상태: 저장됨')),
                PopupMenuItem(value: 'preparing', child: Text('상태: 준비 중')),
                PopupMenuItem(value: 'applied', child: Text('상태: 신청 완료')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'delete', child: Text('삭제')),
              ],
              icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textSecondary),
            ),
          ]),
          const SizedBox(height: 10),
          Text(record.serviceName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Row(children: [
            // 서류 체크 진행률
            if (hasChecklist) ...[
              Icon(Icons.checklist_outlined, size: 13, color: categoryColor),
              const SizedBox(width: 4),
              Text('서류 ${record.checkedCount}/${record.docs.length}',
                  style: TextStyle(fontSize: 12, color: categoryColor, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
            ],
            // 전화번호
            if (record.phone.isNotEmpty) ...[
              Icon(Icons.phone_outlined, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(record.phone,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
            // 메모
            if (record.memo.isNotEmpty) ...[
              const Spacer(),
              Icon(Icons.edit_note, size: 14, color: Colors.grey.shade400),
            ],
          ]),
          // 서류 진행 바
          if (hasChecklist) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: record.docs.isEmpty ? 0 : record.checkedCount / record.docs.length,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(categoryColor),
                minHeight: 4,
              ),
            ),
          ],
        ]),
      ),
    );
  }

  (Color, IconData) _statusStyle(String status) {
    switch (status) {
      case 'preparing': return (Colors.orange.shade700, Icons.pending_outlined);
      case 'applied':   return (AppTheme.success, Icons.check_circle_outline);
      default:          return (AppTheme.primary, Icons.bookmark_outline);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}';
  }
}
