import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/application_provider.dart';
import '../../models/application_record.dart';
import '../../config/app_theme.dart';

class ApplicationDetailScreen extends StatefulWidget {
  final String serviceId;
  const ApplicationDetailScreen({super.key, required this.serviceId});

  @override
  State<ApplicationDetailScreen> createState() => _ApplicationDetailScreenState();
}

class _ApplicationDetailScreenState extends State<ApplicationDetailScreen> {
  ApplicationRecord? _record;
  final _memoCtrl = TextEditingController();

  bool _isValidExternalUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return false;
    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  @override
  void initState() {
    super.initState();
    final record = context.read<ApplicationProvider>().get(widget.serviceId);
    if (record != null) {
      _record = record;
      _memoCtrl.text = record.memo;
    }
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final record = _record;
    if (record == null) return;
    record.memo = _memoCtrl.text.trim();
    await context.read<ApplicationProvider>().update(record);
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    if (record == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('신청 상세')),
        body: const Center(
          child: Text(
            '신청 정보를 찾을 수 없습니다.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }
    final categoryColor = AppTheme.categoryColors[record.category] ?? AppTheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(record.serviceName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // ── 상태 변경 ─────────────────────────────────
          _buildStatusSelector(),
          const SizedBox(height: 20),

          // ── 신청 서류 체크리스트 ──────────────────────
          if (record.docs.isNotEmpty) ...[
            _sectionHeader(Icons.checklist_outlined, '신청 서류 체크리스트', categoryColor),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                children: record.docs.asMap().entries.map((entry) {
                  final i = entry.key;
                  final doc = entry.value;
                  final isLast = i == record.docs.length - 1;
                  return Column(children: [
                    InkWell(
                      onTap: () {
                        setState(() => record.checkedDocs[i] = !record.checkedDocs[i]);
                        _save();
                      },
                      borderRadius: BorderRadius.vertical(
                        top: i == 0 ? const Radius.circular(12) : Radius.zero,
                        bottom: isLast ? const Radius.circular(12) : Radius.zero,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(children: [
                          Icon(
                            record.checkedDocs[i] ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 22,
                            color: record.checkedDocs[i] ? categoryColor : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(doc,
                              style: TextStyle(
                                fontSize: 14,
                                color: record.checkedDocs[i]
                                    ? Colors.grey.shade400
                                    : AppTheme.textPrimary,
                                decoration: record.checkedDocs[i]
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    if (!isLast) Divider(height: 1, color: Colors.grey.shade100, indent: 52),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── 신청처 정보 ───────────────────────────────
          if (record.phone.isNotEmpty || record.address.isNotEmpty) ...[
            _sectionHeader(Icons.place_outlined, '신청처 정보', categoryColor),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (record.phone.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _call(record.phone),
                    child: Row(children: [
                      const Icon(Icons.phone_outlined, size: 16, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Text(record.phone,
                          style: const TextStyle(
                              fontSize: 15, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('전화',
                            style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ],
                if (record.phone.isNotEmpty && record.address.isNotEmpty)
                  Divider(height: 20, color: Colors.grey.shade100),
                if (record.address.isNotEmpty)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.place_outlined, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(record.address,
                          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.5)),
                    ),
                  ]),
              ]),
            ),
            const SizedBox(height: 20),
          ],

          // ── 복지로 바로가기 ───────────────────────────
          if (_isValidExternalUrl(record.onlineUrl)) ...[
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(record.onlineUrl!.trim());
                if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('복지로에서 자세히 보기'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: const Color(0xFF1565C0),
                side: const BorderSide(color: Color(0xFF1565C0)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── 메모 ─────────────────────────────────────
          _sectionHeader(Icons.edit_note, '메모', Colors.grey.shade600),
          const SizedBox(height: 10),
          TextField(
            controller: _memoCtrl,
            maxLines: 5,
            onChanged: (_) => _save(),
            decoration: InputDecoration(
              hintText: '신청 관련 메모를 입력하세요.\n예) 담당자 이름, 방문 예약일, 추가 안내 등',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400, height: 1.6),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: categoryColor, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStatusSelector() {
    final record = _record;
    if (record == null) return const SizedBox.shrink();
    final statuses = [
      ('saved',      '저장됨',    Icons.bookmark_outline,       AppTheme.primary),
      ('preparing',  '준비 중',   Icons.pending_outlined,        Colors.orange.shade700),
      ('applied',    '신청 완료', Icons.check_circle_outline,   AppTheme.success),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('진행 상태',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        const SizedBox(height: 12),
        Row(children: statuses.map((s) {
          final isSelected = record.status == s.$1;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: s.$1 != 'applied' ? 8 : 0),
              child: GestureDetector(
                onTap: () {
                  setState(() => record.status = s.$1);
                  _save();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? s.$4.withValues(alpha: 0.12) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isSelected ? s.$4 : Colors.grey.shade200,
                        width: isSelected ? 1.5 : 1),
                  ),
                  child: Column(children: [
                    Icon(s.$3, size: 20, color: isSelected ? s.$4 : Colors.grey.shade400),
                    const SizedBox(height: 4),
                    Text(s.$2,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                            color: isSelected ? s.$4 : Colors.grey.shade400)),
                  ]),
                ),
              ),
            ),
          );
        }).toList()),
      ]),
    );
  }

  Widget _sectionHeader(IconData icon, String title, Color color) => Row(children: [
    Icon(icon, size: 16, color: color),
    const SizedBox(width: 6),
    Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
  ]);

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제'),
        content: const Text('신청 관리에서 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<ApplicationProvider>().remove(_record!.serviceId);
      if (mounted) Navigator.pop(context);
    }
  }
}
