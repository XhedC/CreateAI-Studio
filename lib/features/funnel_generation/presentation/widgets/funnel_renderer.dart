import 'package:flutter/material.dart';

import '../../data/models/funnel_schema.dart';
import 'lead_form_widget.dart';
import 'public_lead_form_widget.dart';

Color _parseHex(String hex, Color fallback) {
  try {
    var value = hex.replaceFirst('#', '');
    if (value.length == 3) {
      value = value.split('').map((c) => '$c$c').join();
    }
    return Color(int.parse('FF$value', radix: 16));
  } catch (_) {
    return fallback;
  }
}

/// Renders a validated [FunnelSchema] as real, structured Flutter widgets -
/// never raw HTML. Each section type maps to its own small builder method;
/// an unrecognized type (a future schema version, or a section the AI typed
/// as "custom") falls back to a plain card instead of crashing, per the
/// brief's "never blindly render malformed data."
///
/// Used by both the Funnel Preview screen (mobile/tablet/desktop modes) and
/// as the read-only live preview a save reflects - the SAME renderer, no
/// separate hard-coded per-device layouts, since only the surrounding
/// max-width constraint changes between device modes (see
/// funnel_preview_screen.dart).
class FunnelRenderer extends StatelessWidget {
  const FunnelRenderer({
    super.key,
    required this.schema,
    this.funnelId,
    this.publicSlug,
    this.onlyVisible = true,
  });

  final FunnelSchema schema;

  /// Needed to let the lead_form section actually submit into
  /// `funnel_leads` scoped to this funnel via the OWNER's own session
  /// (Phase 5 preview path). Null in contexts where that isn't meaningful
  /// (e.g. a thumbnail-only render, or the public view below).
  final String? funnelId;

  /// When set, renders the lead_form section for a fully anonymous public
  /// visitor instead (see [PublicLeadFormWidget]) - used only by the
  /// public funnel view (Phase 7). Takes precedence over [funnelId] if
  /// both were somehow provided, since a public page must never expose
  /// the authenticated-owner submission path.
  final String? publicSlug;

  /// The live Preview screen only shows visible sections; the Editor's own
  /// section list (not this widget) is what lets hidden sections be seen
  /// and toggled back on.
  final bool onlyVisible;

  @override
  Widget build(BuildContext context) {
    final primary = _parseHex(schema.theme.primaryColor, Theme.of(context).colorScheme.primary);
    final background = _parseHex(schema.theme.backgroundColor, Colors.white);
    final text = _parseHex(schema.theme.textColor, Colors.black87);
    final sections = onlyVisible ? schema.sections.where((s) => s.visible) : schema.sections;

    return Container(
      color: background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in sections)
            DefaultTextStyle.merge(
              style: TextStyle(color: text, fontFamily: schema.theme.fontFamily),
              child: _buildSection(context, section, primary, text),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, FunnelSection section, Color primary, Color text) {
    final type = FunnelSectionType.fromValue(section.type);
    switch (type) {
      case FunnelSectionType.hero:
        return _hero(context, section, primary);
      case FunnelSectionType.navigation:
        return _navigation(context, section, primary);
      case FunnelSectionType.benefits:
      case FunnelSectionType.features:
      case FunnelSectionType.services:
      case FunnelSectionType.products:
        return _itemGrid(context, section, primary);
      case FunnelSectionType.pricing:
        return _pricing(context, section, primary);
      case FunnelSectionType.testimonials:
        return _testimonials(context, section);
      case FunnelSectionType.statistics:
        return _statistics(context, section, primary);
      case FunnelSectionType.about:
      case FunnelSectionType.contact:
        return _textBlock(context, section);
      case FunnelSectionType.faq:
        return _faq(context, section);
      case FunnelSectionType.leadForm:
        return _leadForm(context, section, primary);
      case FunnelSectionType.appointmentCta:
        return _cta(context, section, primary, isAppointment: true);
      case FunnelSectionType.finalCta:
        return _cta(context, section, primary, isAppointment: false);
      case FunnelSectionType.footer:
        return _footer(context, section);
      case FunnelSectionType.custom:
      case null:
        return _fallback(context, section);
    }
  }

  Padding _sectionPadding(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: child,
      );

  Widget _hero(BuildContext context, FunnelSection section, Color primary) {
    final c = section.content;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      color: primary.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c['image'] is String)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                c['image'] as String,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (c['image'] is String) const SizedBox(height: 20),
          Text(
            (c['headline'] as String?) ?? schema.name,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (c['subheadline'] is String)
            Text(c['subheadline'] as String, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white),
            onPressed: () {},
            child: Text((c['cta'] as String?) ?? 'Get Started'),
          ),
        ],
      ),
    );
  }

  Widget _navigation(BuildContext context, FunnelSection section, Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: primary.withValues(alpha: 0.2)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            schema.metadata.businessName.isNotEmpty ? schema.metadata.businessName : schema.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Icon(Icons.menu_rounded, color: primary),
        ],
      ),
    );
  }

  Widget _itemGrid(BuildContext context, FunnelSection section, Color primary) {
    final c = section.content;
    final items = (c['items'] as List?)?.cast<Map>() ?? const [];
    return _sectionPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c['title'] is String)
            Text(c['title'] as String, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final item in items)
                SizedBox(
                  width: 220,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item['title'] is String)
                            Text(
                              item['title'] as String,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          if (item['description'] is String) ...[
                            const SizedBox(height: 6),
                            Text(item['description'] as String,
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pricing(BuildContext context, FunnelSection section, Color primary) {
    final c = section.content;
    final plans = (c['plans'] as List?)?.cast<Map>() ?? const [];
    return _sectionPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c['title'] is String)
            Text(c['title'] as String, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final plan in plans)
                SizedBox(
                  width: 220,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((plan['name'] as String?) ?? 'Plan',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text((plan['price'] as String?) ?? '',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: primary)),
                          for (final feature in (plan['features'] as List?) ?? const [])
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('• $feature', style: Theme.of(context).textTheme.bodySmall),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _testimonials(BuildContext context, FunnelSection section) {
    final c = section.content;
    final items = (c['items'] as List?)?.cast<Map>() ?? const [];
    return _sectionPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c['title'] is String)
            Text(c['title'] as String, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('"${item['quote'] ?? ''}"',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                            )),
                    const SizedBox(height: 6),
                    Text('- ${item['author'] ?? 'Anonymous'}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statistics(BuildContext context, FunnelSection section, Color primary) {
    final c = section.content;
    final items = (c['items'] as List?)?.cast<Map>() ?? const [];
    return _sectionPadding(
      Wrap(
        spacing: 24,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          for (final item in items)
            Column(
              children: [
                Text((item['value'] as String?) ?? '',
                    style:
                        Theme.of(context).textTheme.headlineMedium?.copyWith(color: primary)),
                Text((item['label'] as String?) ?? '', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
        ],
      ),
    );
  }

  Widget _textBlock(BuildContext context, FunnelSection section) {
    final c = section.content;
    return _sectionPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c['title'] is String)
            Text(c['title'] as String, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          if (c['description'] is String)
            Text(c['description'] as String, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _faq(BuildContext context, FunnelSection section) {
    final c = section.content;
    final items = (c['items'] as List?)?.cast<Map>() ?? const [];
    return _sectionPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c['title'] is String)
            Text(c['title'] as String, style: Theme.of(context).textTheme.headlineSmall),
          for (final item in items)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text((item['question'] as String?) ?? ''),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text((item['answer'] as String?) ?? ''),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _leadForm(BuildContext context, FunnelSection section, Color primary) {
    final c = section.content;
    return _sectionPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c['title'] is String)
            Text(c['title'] as String, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          if (publicSlug != null)
            PublicLeadFormWidget(
              slug: publicSlug!,
              submitLabel: (c['submitLabel'] as String?) ?? 'Submit',
            )
          else if (funnelId != null)
            LeadFormWidget(funnelId: funnelId!, submitLabel: (c['submitLabel'] as String?) ?? 'Submit')
          else
            Text(
              'Lead form preview (save this funnel to enable submissions).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _cta(BuildContext context, FunnelSection section, Color primary, {required bool isAppointment}) {
    final c = section.content;
    return _sectionPadding(
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Text(
              (c['headline'] as String?) ?? (c['title'] as String?) ?? 'Ready to get started?',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: primary),
              onPressed: () {
                if (isAppointment) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Appointment booking is coming in a future update.')),
                  );
                }
              },
              icon: Icon(isAppointment ? Icons.calendar_month_rounded : Icons.arrow_forward_rounded),
              label: Text((c['cta'] as String?) ?? (isAppointment ? 'Book Now' : 'Get Started')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, FunnelSection section) {
    final c = section.content;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Text(
            (c['businessName'] as String?) ?? schema.metadata.businessName,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (c['tagline'] is String) ...[
            const SizedBox(height: 4),
            Text(c['tagline'] as String, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _fallback(BuildContext context, FunnelSection section) {
    final c = section.content;
    return _sectionPadding(
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          (c['title'] as String?) ?? 'Section: ${section.type}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
