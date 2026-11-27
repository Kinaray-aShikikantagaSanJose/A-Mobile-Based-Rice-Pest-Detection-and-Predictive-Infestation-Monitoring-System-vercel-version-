import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../models/record.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import 'app_widgets.dart';

/// Corrects the land type of a record that is already on the server (needs
/// signal). The server decides who may: the submitter before review,
/// technicians for records in their coverage. Returns the updated record,
/// or null if nothing changed.
Future<Record?> showLandTypeChange(BuildContext context, Record record, {bool askReason = false}) {
  return showModalBottomSheet<Record>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LandTypeSheet(record: record, askReason: askReason),
  );
}

class _LandTypeSheet extends StatefulWidget {
  final Record record;
  final bool askReason;
  const _LandTypeSheet({required this.record, required this.askReason});

  @override
  State<_LandTypeSheet> createState() => _LandTypeSheetState();
}

class _LandTypeSheetState extends State<_LandTypeSheet> {
  late String? _choice = widget.record.landType.isEmpty ? null : widget.record.landType;
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;
  String? _error; // English; shown translated

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = widget.record.id;
    if (id == null || _choice == null) return;
    if (_choice == widget.record.landType) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await SyncService.changeLandType(id, _choice!, reason: _reason.text);
      if (mounted) Navigator.pop(context, updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.isOffline ? 'No signal. Changing the land type needs a connection; try again with signal.' : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('Change the land type'),
                  style: const TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                context.tr('Pick what best describes this field. The change is saved with your name and the time.'),
                style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.md),
              RadioGroup<String>(
                groupValue: _choice,
                onChanged: (v) {
                  if (!_busy) setState(() => _choice = v);
                },
                child: Column(
                  children: [
                    for (final (key, label, hint) in kLandTypes)
                      RadioListTile<String>(
                        value: key,
                        contentPadding: EdgeInsets.zero,
                        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(hint),
                      ),
                  ],
                ),
              ),
              if (widget.askReason) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _reason,
                  enabled: !_busy,
                  maxLength: 300,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: context.tr('Reason (optional)')),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(context.tr(_error!), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: AppSpacing.md),
              AppPrimaryButton(
                label: context.tr('Save land type'),
                icon: Icons.check_rounded,
                loading: _busy,
                onPressed: _choice == null ? null : _save,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(context.tr('Cancel'), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
