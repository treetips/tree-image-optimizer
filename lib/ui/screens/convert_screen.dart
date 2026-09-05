import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../app/providers.dart';
import '../../core/models/file_progress.dart';
import '../../core/models/optimize_type.dart';
import '../../core/models/output_format.dart';
import '../../core/models/process_status.dart';
import '../../core/models/target_filter.dart';
import '../../logic/viewmodels/convert_view_model.dart';
import '../theme/app_colors.dart';
import '../theme/glass_constants.dart';
import '../widgets/glass_button.dart';
import '../widgets/section.dart';
import '../widgets/status.dart';
import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

/// 画像変換画面。
class ConvertScreen extends ConsumerStatefulWidget {
  const ConvertScreen({super.key});

  @override
  ConsumerState<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends ConsumerState<ConvertScreen> {
  Future<void> _selectFolder(WidgetRef ref, bool isInput) async {
    final directory = await getDirectoryPath();
    if (directory == null) return;
    final viewModel = ref.read(convertViewModelProvider.notifier);
    if (isInput) {
      viewModel.setInputFolderPath(directory);
    } else {
      viewModel.setOutputFolderPath(directory);
    }
  }

  /// 変換完了を検知してスナックバーを表示する。
  void _showCompletionSnackBar(ConvertState state) {
    final allSuccess =
        state.totalCount > 0 &&
        state.failureCount == 0 &&
        state.successCount > 0;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Expanded(child: Text(l10n.conversionComplete)),
              TextButton(
                onPressed: messenger.hideCurrentSnackBar,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(l10n.close),
              ),
            ],
          ),
          duration: const Duration(seconds: 5),
          backgroundColor: allSuccess ? Colors.green : Colors.red,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(convertViewModelProvider, (previous, next) {
      if (previous != null &&
          previous.isRunning &&
          !next.isRunning &&
          next.totalCount > 0) {
        _showCompletionSnackBar(next);
      }
    });

    final state = ref.watch(convertViewModelProvider);
    final viewModel = ref.read(convertViewModelProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _FormView(
        state: state,
        viewModel: viewModel,
        onSelect: (isInput) => _selectFolder(ref, isInput),
        showResult: state.isRunning || state.fileProgress.isNotEmpty,
      ),
    );
  }
}

/// 入力フォームビュー。
class _FormView extends ConsumerStatefulWidget {
  const _FormView({
    required this.state,
    required this.viewModel,
    required this.onSelect,
    required this.showResult,
  });

  final ConvertState state;
  final ConvertViewModel viewModel;
  final void Function(bool isInput) onSelect;
  final bool showResult;

  @override
  ConsumerState<_FormView> createState() => _FormViewState();
}

class _FormViewState extends ConsumerState<_FormView> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _resultKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _resultKey.currentContext;
      if (context == null || !_scrollController.hasClients) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(convertViewModelProvider, (previous, next) {
      if (previous != null && !previous.isRunning && next.isRunning) {
        _scrollToResult();
      }
    });

    final state = widget.state;
    final viewModel = widget.viewModel;
    final onSelect = widget.onSelect;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: l10n.sectionInput,
          child: Column(
            children: [
              _FieldRow(
                label: l10n.fieldTargetFolder,
                info: l10n.infoTargetFolder,
                control: _FolderField(
                  path: state.inputFolderPath,
                  hasError: state.inputFolderError,
                  onSelect: () => onSelect(true),
                  onChanged: viewModel.setInputFolderPath,
                ),
              ),
              const SizedBox(height: 8),
              _FieldRow(
                label: l10n.fieldTargetFiles,
                info: l10n.infoTargetFiles,
                control: _DropdownField<TargetFilter>(
                  value: state.targetFilter,
                  items: TargetFilter.values,
                  labelOf: (f) => f.label(l10n),
                  onChanged: (f) {
                    if (f != null) viewModel.setTargetFilter(f);
                  },
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: l10n.sectionUpscale,
          child: Column(
            children: [
              _FieldRow(
                label: l10n.fieldScale,
                info: l10n.infoScale,
                control: _SliderField(
                  value: state.scale.toDouble(),
                  min: 1,
                  max: 4,
                  interval: 1,
                  display: '${state.scale}',
                  trackShape: const _SegmentedTrackShape(
                    min: 1,
                    max: 4,
                    boundaries: [0, 1 / 3, 2 / 3, 1],
                  ),
                  onChanged: (v) => viewModel.setScale(v.round()),
                ),
              ),
              const SizedBox(height: 8),
              _FieldRow(
                label: l10n.fieldModel,
                info: l10n.infoModel,
                control: _DropdownField<String>(
                  value: state.selectedModel,
                  items: state.models.isEmpty
                      ? const ['realesr-animevideov3-x4']
                      : state.models,
                  labelOf: (m) => m,
                  onChanged: (m) {
                    if (m != null) viewModel.setSelectedModel(m);
                  },
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: l10n.sectionCompress,
          child: Column(
            children: [
              _FieldRow(
                label: l10n.fieldFormat,
                info: l10n.infoFormat,
                control: _DropdownField<OutputFormat>(
                  value: state.format,
                  items: OutputFormat.values,
                  labelOf: (f) => f.label(l10n),
                  onChanged: (f) {
                    if (f != null) viewModel.setFormat(f);
                  },
                ),
              ),
              const SizedBox(height: 8),
              _FieldRow(
                label: l10n.fieldOptimizeType,
                info: l10n.infoOptimizeType,
                control: _DropdownField<OptimizeType>(
                  value: state.optimizeType,
                  items: OptimizeType.values,
                  labelOf: (t) => t.label(l10n),
                  onChanged: (t) {
                    if (t != null) viewModel.setOptimizeType(t);
                  },
                ),
              ),
              const SizedBox(height: 8),
              _FieldRow(
                label: l10n.fieldQuality,
                info: l10n.infoFormat,
                control: _SliderField(
                  value: state.quality.toDouble(),
                  min: 1,
                  max: 100,
                  interval: 10,
                  display: '${state.quality}',
                  horizontalPadding: 16,
                  endLabel: '100',
                  trackShape: const _SegmentedTrackShape(
                    min: 1,
                    max: 100,
                    boundaries: [0, 79 / 99, 89 / 99, 1],
                  ),
                  labelFormatter: (value) {
                    if (value <= 1) return '1';
                    if (value >= 100) return '100';
                    return ((((value - 1) / 10).round()) * 10).toString();
                  },
                  onChanged: (v) => viewModel.setQuality(v.round()),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: l10n.sectionProcess,
          child: _FieldRow(
            label: l10n.fieldParallel,
            info: l10n.infoParallel,
            control: _SliderField(
              value: state.parallelCount.toDouble(),
              min: 1,
              max: viewModel.maxParallel.toDouble(),
              interval: 1,
              display: '${state.parallelCount}',
              trackShape: _SegmentedTrackShape(
                min: 1,
                max: viewModel.maxParallel.toDouble(),
                boundaries: const [0, 0.5, 0.75, 1],
              ),
              onChanged: (v) => viewModel.setParallelCount(v.round()),
            ),
          ),
        ),
        SectionCard(
          title: l10n.sectionOutput,
          child: _FieldRow(
            label: l10n.fieldOutputFolder,
            info: l10n.infoOutputFolder,
            control: _FolderField(
              path: state.outputFolderPath,
              hasError: state.outputFolderError,
              onSelect: () => onSelect(false),
              onChanged: viewModel.setOutputFolderPath,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _RunButton(state: state, viewModel: viewModel),
        if (widget.showResult)
          KeyedSubtree(
            key: _resultKey,
            child: Column(
              children: [
                const SizedBox(height: 16),
                SectionCard(
                  title: l10n.result,
                  child: _ResultTable(state: state),
                ),
              ],
            ),
          ),
      ],
    );

    if (!widget.showResult) {
      return Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: content,
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: _BackToTopButton(onPressed: _scrollToTop),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 72),
              child: content,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: GlassConstants.blur,
              child: Container(
                decoration: BoxDecoration(
                  color: GlassConstants.cardColor,
                  border: Border(
                    top: BorderSide(color: GlassConstants.cardBorder, width: 1),
                  ),
                ),
                child: _ResultSummary(state: state),
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 80,
          child: _BackToTopButton(onPressed: _scrollToTop),
        ),
      ],
    );
  }
}

/// 変換実行ボタン。
class _RunButton extends StatelessWidget {
  const _RunButton({required this.state, required this.viewModel});

  final ConvertState state;
  final ConvertViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return GlassRunButton(
      canRun: state.canRun,
      isRunning: state.isRunning,
      onPressed: viewModel.runConversion,
    );
  }
}

/// 画面の先頭に戻るボタン（LiquidGlass・丸形）。
class _BackToTopButton extends StatelessWidget {
  const _BackToTopButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: GlassConstants.backToTopSize,
      height: GlassConstants.backToTopSize,
      child: LiquidGlassLens(
        style: GlassConstants.backToTopLiquidStyle,
        touch: const LiquidGlassTouch(flex: LiquidGlassFlex()),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(
              GlassConstants.backToTopCornerRadius,
            ),
            onTap: onPressed,
            child: const Center(
              child: Text(
                '↑',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 静的ラベル・コントロール・情報アイコンからなるフィールド行。
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.info,
    required this.control,
  });

  final String label;
  final String info;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        const SizedBox(width: 8),
        Expanded(child: control),
        const SizedBox(width: 8),
        InfoTooltip(text: info),
      ],
    );
  }
}

/// フォルダ選択フィールド。
class _FolderField extends StatefulWidget {
  const _FolderField({
    required this.path,
    required this.hasError,
    required this.onSelect,
    required this.onChanged,
  });

  final String? path;
  final bool hasError;
  final VoidCallback onSelect;
  final ValueChanged<String> onChanged;

  @override
  State<_FolderField> createState() => _FolderFieldState();
}

class _FolderFieldState extends State<_FolderField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.path ?? '',
  );

  @override
  void didUpdateWidget(covariant _FolderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path && widget.path != _controller.text) {
      _controller.text = widget.path ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();
    final border = OutlineInputBorder(
      borderSide: BorderSide(
        color: widget.hasError ? AppColors.error : Colors.grey,
        width: widget.hasError ? 2 : 1,
      ),
    );
    return Row(
      children: [
        ElevatedButton(
          onPressed: widget.onSelect,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: Text(l10n.select),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _controller,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              isDense: true,
              border: border,
              enabledBorder: border,
              focusedBorder: border,
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentedTrackShape extends SfTrackShape {
  const _SegmentedTrackShape({
    required this.min,
    required this.max,
    required this.boundaries,
  });

  final double min;
  final double max;
  final List<double> boundaries;

  static const _colors = [
    AppColors.primary,
    Color(0xFFFFC107),
    Color(0xFFE53935),
  ];

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Offset? thumbCenter,
    Offset? startThumbCenter,
    Offset? endThumbCenter, {
    required RenderBox parentBox,
    required SfSliderThemeData themeData,
    SfRangeValues? currentValues,
    dynamic currentValue,
    required Animation<double> enableAnimation,
    required Paint? inactivePaint,
    required Paint? activePaint,
    required TextDirection textDirection,
  }) {
    final trackRect = getPreferredRect(parentBox, themeData, offset);
    final canvas = context.canvas;
    final current = (currentValue as num?)?.toDouble() ?? min;
    final activeRatio = ((current - min) / (max - min)).clamp(0.0, 1.0);
    final radius = Radius.circular(themeData.trackCornerRadius ?? 3);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(trackRect, radius));

    for (var index = 0; index < _colors.length; index++) {
      final start = trackRect.left + trackRect.width * boundaries[index];
      final end = trackRect.left + trackRect.width * boundaries[index + 1];
      final baseRect = Rect.fromLTRB(
        start,
        trackRect.top,
        end,
        trackRect.bottom,
      );
      final basePaint = Paint()..color = _colors[index].withValues(alpha: 0.2);
      canvas.drawRect(baseRect, basePaint);

      final activeEnd = math.min(activeRatio, boundaries[index + 1]);
      if (activeEnd > boundaries[index]) {
        final activeRect = Rect.fromLTRB(
          start,
          trackRect.top,
          trackRect.left + trackRect.width * activeEnd,
          trackRect.bottom,
        );
        canvas.drawRect(activeRect, Paint()..color = _colors[index]);
      }
    }

    canvas.restore();
  }
}

/// Syncfusionスライダーと目盛りを表示するフィールド。
class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.value,
    required this.min,
    required this.max,
    required this.interval,
    required this.display,
    this.horizontalPadding = 0,
    this.endLabel,
    this.trackShape,
    this.labelFormatter,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final double interval;
  final String display;
  final double horizontalPadding;
  final String? endLabel;
  final SfTrackShape? trackShape;
  final String Function(double)? labelFormatter;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodyLarge!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: SfSliderTheme(
                data: SfSliderThemeData(
                  activeTrackHeight: 6,
                  inactiveTrackHeight: 4,
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.primary.withValues(alpha: 0.18),
                  thumbColor: AppColors.primary,
                  activeTickColor: AppColors.primary,
                  inactiveTickColor: Colors.grey.shade400,
                  activeMinorTickColor: AppColors.primary,
                  inactiveMinorTickColor: Colors.grey.shade300,
                  inactiveLabelStyle: labelStyle,
                  activeLabelStyle: labelStyle,
                  thumbRadius: 13,
                ),
                child: SfSlider(
                  min: min,
                  max: max,
                  trackShape: trackShape ?? const SfTrackShape(),
                  value: value.clamp(min, max),
                  interval: interval,
                  stepSize: 1,
                  showTicks: true,
                  showLabels: true,
                  edgeLabelPlacement: EdgeLabelPlacement.inside,
                  minorTicksPerInterval: interval == 1 ? 0 : 1,
                  onLabelCreated:
                      (
                        dynamic actualValue,
                        String formattedText,
                        TextStyle textStyle,
                      ) {
                        return SliderLabel(
                          text:
                              labelFormatter?.call(actualValue as double) ??
                              formattedText,
                          textStyle: textStyle,
                        );
                      },
                  enableTooltip: false,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.primary.withValues(alpha: 0.18),
                  thumbIcon: SizedBox(
                    width: 26,
                    height: 26,
                    child: Center(
                      child: Text(
                        display,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  onChanged: (dynamic nextValue) =>
                      onChanged(nextValue as double),
                ),
              ),
            ),
            if (endLabel != null)
              Positioned(
                right: horizontalPadding,
                bottom: -4,
                child: Text(endLabel!, style: labelStyle),
              ),
          ],
        ),
      ],
    );
  }
}

/// プルダウン付きフィールド。
class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final item in items)
          DropdownMenuItem(value: item, child: Text(labelOf(item))),
      ],
      onChanged: onChanged,
    );
  }
}

/// 実行結果（絞り込み・進捗率・進捗表）。
class _ResultTable extends StatefulWidget {
  const _ResultTable({required this.state});

  final ConvertState state;

  @override
  State<_ResultTable> createState() => _ResultTableState();
}

class _ResultTableState extends State<_ResultTable> {
  final ScrollController _controller = ScrollController();

  /// 各状態の絞り込みチェック状態。初期値は全てチェック済み。
  bool _showWaiting = true;
  bool _showRunning = true;
  bool _showSuccess = true;
  bool _showFailure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// ある行が絞り込み対象かどうか。
  /// `アップスケール` `圧縮` `出力` のいずれか1つでも、チェックした状態を含む場合に表示対象。
  bool _matchesFilter(FileProgress file) {
    final statuses = [
      file.upscaleStatus,
      file.compressStatus,
      file.outputStatus,
    ];
    if (_showWaiting && statuses.contains(ProcessStatus.waiting)) return true;
    if (_showRunning && statuses.contains(ProcessStatus.running)) return true;
    if (_showSuccess && statuses.contains(ProcessStatus.success)) return true;
    if (_showFailure && statuses.contains(ProcessStatus.failure)) return true;
    return false;
  }

  Widget _filterCheckbox({
    required Key key,
    required ProcessStatus status,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(4),
      child: Row(
        children: [
          Checkbox(
            key: key,
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          StatusIndicator(status: status),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _headerCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _statusCell(ProcessStatus status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(child: StatusIndicator(status: status)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();
    final filtered = state.fileProgress.where(_matchesFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _filterCheckbox(
              key: const Key('filter_waiting'),
              status: ProcessStatus.waiting,
              value: _showWaiting,
              onChanged: (v) => setState(() => _showWaiting = v ?? true),
            ),
            _filterCheckbox(
              key: const Key('filter_running'),
              status: ProcessStatus.running,
              value: _showRunning,
              onChanged: (v) => setState(() => _showRunning = v ?? true),
            ),
            _filterCheckbox(
              key: const Key('filter_success'),
              status: ProcessStatus.success,
              value: _showSuccess,
              onChanged: (v) => setState(() => _showSuccess = v ?? true),
            ),
            _filterCheckbox(
              key: const Key('filter_failure'),
              status: ProcessStatus.failure,
              value: _showFailure,
              onChanged: (v) => setState(() => _showFailure = v ?? true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ProgressBar(state: state),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: Scrollbar(
            controller: _controller,
            thumbVisibility: true,
            interactive: true,
            child: SingleChildScrollView(
              key: const Key('resultTableScroll'),
              controller: _controller,
              child: Table(
                border: TableBorder.all(color: Colors.black),
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: AppColors.primary),
                    children: [
                      _headerCell(l10n.fileName),
                      _headerCell(l10n.upscale),
                      _headerCell(l10n.compress),
                      _headerCell(l10n.output),
                    ],
                  ),
                  for (final file in filtered)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: Text(file.fileName)),
                        ),
                        _statusCell(file.upscaleStatus),
                        _statusCell(file.compressStatus),
                        _statusCell(file.outputStatus),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 進捗率バー。バー内にパーセンテージを表示する。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.state});

  final ConvertState state;

  @override
  Widget build(BuildContext context) {
    final ratio = (state.progressPercent / 100).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 24,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFFE0E0E0))),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio,
              child: ColoredBox(
                color: AppColors.primary,
                child: Center(
                  child: Text(
                    '${state.progressPercent.round()}%',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 画面下部に固定する結果サマリー。
class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.state});

  final ConvertState state;

  Widget _cell(
    BuildContext context,
    String label,
    String value, {
    required bool isFirst,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            left: isFirst
                ? BorderSide.none
                : const BorderSide(color: Colors.black),
          ),
        ),
        child: Column(
          children: [
            Text(value, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.black)),
      child: Row(
        children: [
          _cell(
            context,
            l10n.targetFileCount,
            '${state.totalCount}',
            isFirst: true,
          ),
          _cell(
            context,
            l10n.successCount,
            '${state.successCount}',
            isFirst: false,
          ),
          _cell(
            context,
            l10n.failureCount,
            '${state.failureCount}',
            isFirst: false,
          ),
          _cell(
            context,
            l10n.elapsedTime,
            '${state.elapsedMinutes.toStringAsFixed(1)}${l10n.minuteUnit}',
            isFirst: false,
          ),
        ],
      ),
    );
  }
}
