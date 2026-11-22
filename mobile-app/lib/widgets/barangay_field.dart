import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/antique_geofence.dart';
import '../theme.dart';

/// Barangay text field that suggests the official barangays of the chosen
/// municipality (offline list of all 590 in Antique). Typing is still
/// allowed; a typed name that matches an official one is recognised later
/// (see [AntiqueGeofence.match]).
class BarangayField extends StatefulWidget {
  final TextEditingController controller;
  final String municipality;
  final InputDecoration decoration;
  final String? Function(String?)? validator;
  final TextStyle? style;

  /// A suggestion was picked (null when the person types freely).
  final ValueChanged<GeoPlace?>? onPlace;
  final int? maxLength;

  const BarangayField({
    super.key,
    required this.controller,
    required this.municipality,
    this.decoration = const InputDecoration(),
    this.validator,
    this.style,
    this.onPlace,
    this.maxLength,
  });

  @override
  State<BarangayField> createState() => _BarangayFieldState();
}

class _BarangayFieldState extends State<BarangayField> {
  final FocusNode _focus = FocusNode();
  List<GeoPlace> _options = const [];
  String _loadedFor = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BarangayField old) {
    super.didUpdateWidget(old);
    if (old.municipality != widget.municipality) _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final m = widget.municipality;
    if (m.isEmpty) {
      setState(() => _options = const []);
      return;
    }
    try {
      final list = await AntiqueGeofence.instance.barangaysOf(m);
      if (!mounted || widget.municipality != m) return;
      setState(() {
        _options = list;
        _loadedFor = m;
      });
    } catch (e) {
      debugPrint('[Places] barangay list not loaded: $e');
    }
  }

  Iterable<GeoPlace> _matches(TextEditingValue value) {
    if (_loadedFor != widget.municipality) return const [];
    final q = AntiqueGeofence.norm(value.text);
    if (q.isEmpty) return _options;
    final starts = _options.where((p) => AntiqueGeofence.norm(p.barangay).startsWith(q));
    final contains = _options.where((p) {
      final n = AntiqueGeofence.norm(p.barangay);
      return !n.startsWith(q) && n.contains(q);
    });
    return [...starts, ...contains];
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<GeoPlace>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: _matches,
      displayStringForOption: (p) => p.barangay,
      onSelected: (p) => widget.onPlace?.call(p),
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextFormField(
        controller: controller,
        focusNode: focusNode,
        maxLength: widget.maxLength,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        validator: widget.validator,
        style: widget.style,
        decoration: widget.decoration.copyWith(
          helperText: widget.municipality.isEmpty ? null : context.tr('Type to see the barangays of {municipality}.', {'municipality': widget.municipality}),
        ),
        onChanged: (_) => widget.onPlace?.call(null),
        onFieldSubmitted: (_) => onSubmitted(),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260, maxWidth: 420),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final p in options)
                  ListTile(
                    dense: true,
                    title: Text(p.barangay, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(p.municipality, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    onTap: () => onSelected(p),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
