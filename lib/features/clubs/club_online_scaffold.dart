import 'package:flutter/material.dart';

/// The same soft diagonal background used by the initial password choice.
const clubOnlineGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xffe6dbf3), Color(0xfffaf7fc), Color(0xffdeeddb)],
);

/// Shared background for setup. Content sits directly on the gradient;
/// only individual fields and guidance cards have their own light surfaces.
class ClubOnlineScaffold extends StatelessWidget {
  const ClubOnlineScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.constrainBody = true,
  });
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final bool constrainBody;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: clubOnlineGradient),
    child: Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: Theme.of(context).appBarTheme.copyWith(
          backgroundColor: Colors.transparent,
          foregroundColor: const Color(0xff624591),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
          filled: true,
          fillColor: const Color(0xBFFFFFFF),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: constrainBody
            ? Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Material(
                      type: MaterialType.transparency,
                      child: body,
                    ),
                  ),
                ),
              )
            : body,
        bottomNavigationBar: bottomNavigationBar == null
            ? null
            : Material(
                type: MaterialType.transparency,
                child: bottomNavigationBar,
              ),
      ),
    ),
  );
}

/// The same quiet gradient on short onboarding confirmations.
class ClubOnlineDialog extends StatelessWidget {
  const ClubOnlineDialog({
    super.key,
    required this.title,
    this.content,
    this.actions,
  });
  final Widget title;
  final Widget? content;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: clubOnlineGradient),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DefaultTextStyle(
                  style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                    color: const Color(0xff624591),
                  ),
                  child: Semantics(namesRoute: true, child: title),
                ),
                if (content != null) ...[
                  const SizedBox(height: 18),
                  Flexible(child: SingleChildScrollView(child: content!)),
                ],
                if (actions != null) ...[
                  const SizedBox(height: 24),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 8,
                    children: actions!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
