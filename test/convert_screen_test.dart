import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tree_image_optimizer/app/providers.dart';
import 'package:tree_image_optimizer/core/models/optimize_type.dart';
import 'package:tree_image_optimizer/core/models/output_format.dart';
import 'package:tree_image_optimizer/core/models/result.dart';
import 'package:tree_image_optimizer/core/models/target_filter.dart';
import 'package:tree_image_optimizer/data/repositories/convert_repository.dart';
import 'package:tree_image_optimizer/data/services/compression_service.dart';
import 'package:tree_image_optimizer/data/services/path_service.dart';
import 'package:tree_image_optimizer/data/services/process_service.dart';
import 'package:tree_image_optimizer/data/services/upscale_service.dart';
import 'package:tree_image_optimizer/logic/usecases/compress_usecase.dart';
import 'package:tree_image_optimizer/logic/usecases/get_target_files_usecase.dart';
import 'package:tree_image_optimizer/logic/usecases/get_upscale_models_usecase.dart';
import 'package:tree_image_optimizer/logic/usecases/upscale_usecase.dart';
import 'package:tree_image_optimizer/logic/viewmodels/convert_view_model.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as loc;
import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';
import 'package:tree_image_optimizer/ui/screens/convert_screen.dart';

ConvertRepository _fakeRepository() {
  final pathService = PathService();
  return ConvertRepository(
    pathService: pathService,
    upscaleService: UpscaleService(
      pathService: pathService,
      processService: ProcessService(),
    ),
    compressionService: CompressionService(
      pathService: pathService,
      processService: ProcessService(),
    ),
  );
}

class _FakeGetTargetFilesUseCase extends GetTargetFilesUseCase {
  _FakeGetTargetFilesUseCase(this.files) : super(_fakeRepository());
  final List<String> files;

  @override
  Future<Result<List<String>>> execute(String folderPath, TargetFilter filter) {
    return Future.value(Result.ok(files));
  }
}

class _FakeGetUpscaleModelsUseCase extends GetUpscaleModelsUseCase {
  _FakeGetUpscaleModelsUseCase() : super(_fakeRepository());

  @override
  Future<List<String>> execute() {
    return Future.value(const ['realesr-animevideov3-x4']);
  }
}

class _FakeUpscaleUseCase extends UpscaleUseCase {
  _FakeUpscaleUseCase({this.shouldFail = false}) : super(_fakeRepository());
  final bool shouldFail;

  @override
  Future<Result<void>> execute({
    required String input,
    required String output,
    required int scale,
    required String model,
  }) {
    if (shouldFail) return Future.value(Result.fail('upscale error'));
    File(output).writeAsStringSync('upscaled');
    return Future.value(Result.ok(null));
  }
}

class _FakeCompressUseCase extends CompressUseCase {
  _FakeCompressUseCase({this.shouldFailForBbb = false})
    : super(_fakeRepository());
  final bool shouldFailForBbb;

  @override
  Future<Result<void>> execute({
    required String input,
    required String output,
    required OutputFormat format,
    required OptimizeType optimizeType,
    required int quality,
    required int threads,
  }) {
    if (shouldFailForBbb && input.contains('bbb')) {
      return Future.value(Result.fail('compress error'));
    }
    File(output).writeAsStringSync('compressed');
    return Future.value(Result.ok(null));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .localeTestValue = const Locale(
    'ja',
  );
  late Directory tempDir;
  late Directory inputDir;
  late Directory outputDir;
  late ConvertViewModel viewModel;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('convert_screen_test');
    inputDir = Directory('${tempDir.path}/input')..createSync();
    outputDir = Directory('${tempDir.path}/output')..createSync();

    viewModel = ConvertViewModel(
      getTargetFilesUseCase: _FakeGetTargetFilesUseCase([
        '${inputDir.path}/aaa.png',
        '${inputDir.path}/bbb.png',
      ]),
      getUpscaleModelsUseCase: _FakeGetUpscaleModelsUseCase(),
      upscaleUseCase: _FakeUpscaleUseCase(),
      compressUseCase: _FakeCompressUseCase(),
      processorCount: 4,
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Widget buildApp([ConvertViewModel? vm]) {
    return ProviderScope(
      overrides: [
        convertViewModelProvider.overrideWith((ref) => vm ?? viewModel),
      ],
      child: MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          loc.GlobalMaterialLocalizations.delegate,
          loc.GlobalWidgetsLocalizations.delegate,
          loc.GlobalCupertinoLocalizations.delegate,
        ],
        home: const ConvertScreen(),
      ),
    );
  }

  testWidgets('全成功時に緑色の変換完了スナックバーが表示される', (tester) async {
    viewModel.setInputFolderPath(inputDir.path);
    viewModel.setOutputFolderPath(outputDir.path);

    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.runAsync(() => viewModel.runConversion());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('変換完了'), findsOneWidget);

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.backgroundColor, Colors.green);
    expect(find.text('閉じる'), findsOneWidget);
  });

  testWidgets('失敗時に赤色の変換完了スナックバーが表示される', (tester) async {
    final failingVm = ConvertViewModel(
      getTargetFilesUseCase: _FakeGetTargetFilesUseCase([
        '${inputDir.path}/aaa.png',
      ]),
      getUpscaleModelsUseCase: _FakeGetUpscaleModelsUseCase(),
      upscaleUseCase: _FakeUpscaleUseCase(shouldFail: true),
      compressUseCase: _FakeCompressUseCase(),
      processorCount: 4,
    );
    failingVm.setInputFolderPath(inputDir.path);
    failingVm.setOutputFolderPath(outputDir.path);

    await tester.pumpWidget(buildApp(failingVm));
    await tester.pump();

    await tester.runAsync(() => failingVm.runConversion());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.backgroundColor, Colors.red);
    expect(find.text('変換完了'), findsOneWidget);
  });

  testWidgets('変換完了スナックバーは5秒で自動非表示になる', (tester) async {
    viewModel.setInputFolderPath(inputDir.path);
    viewModel.setOutputFolderPath(outputDir.path);

    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.runAsync(() => viewModel.runConversion());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('変換完了'), findsOneWidget);

    // 5秒経過で自動非表示になる。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('変換完了'), findsNothing);
  });

  testWidgets('少数件数では300px以内に収まりスクロール不要', (tester) async {
    // 少数件数(例: 1日以内に更新されたファイル)では高さが300pxに収まる。
    final few = List.generate(5, (i) => '${inputDir.path}/file$i.png');
    final vm = ConvertViewModel(
      getTargetFilesUseCase: _FakeGetTargetFilesUseCase(few),
      getUpscaleModelsUseCase: _FakeGetUpscaleModelsUseCase(),
      upscaleUseCase: _FakeUpscaleUseCase(),
      compressUseCase: _FakeCompressUseCase(),
      processorCount: 4,
    );
    vm.setInputFolderPath(inputDir.path);
    vm.setOutputFolderPath(outputDir.path);

    await tester.pumpWidget(buildApp(vm));
    await tester.pump();
    await tester.runAsync(() => vm.runConversion());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scrollView = find.byKey(const Key('resultTableScroll'));
    final size = tester.getSize(scrollView);
    // 高さが300px以下(実際は収まっている)であり、スクロール不要。
    expect(size.height, lessThan(300));
    final scrollable = tester.widget<SingleChildScrollView>(scrollView);
    expect(scrollable.controller!.position.maxScrollExtent, 0);
  });

  testWidgets('描画高さが300pxを超えるとスクロールバーが表示される', (tester) async {
    // 行数ではなく描画高さが300pxを超えるよう十分なデータを用意する。
    final many = List.generate(200, (i) => '${inputDir.path}/file$i.png');
    final bigVm = ConvertViewModel(
      getTargetFilesUseCase: _FakeGetTargetFilesUseCase(many),
      getUpscaleModelsUseCase: _FakeGetUpscaleModelsUseCase(),
      upscaleUseCase: _FakeUpscaleUseCase(),
      compressUseCase: _FakeCompressUseCase(),
      processorCount: 8,
    );
    bigVm.setInputFolderPath(inputDir.path);
    bigVm.setOutputFolderPath(outputDir.path);

    await tester.pumpWidget(buildApp(bigVm));
    await tester.pump();
    await tester.runAsync(() => bigVm.runConversion());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scrollView = find.byKey(const Key('resultTableScroll'));
    expect(scrollView, findsOneWidget);

    final size = tester.getSize(scrollView);
    expect(size.height, lessThanOrEqualTo(300));

    // コンテンツが高さを超え、スクロール可能である。
    final scrollable = tester.widget<SingleChildScrollView>(scrollView);
    expect(scrollable.controller!.hasClients, isTrue);
    expect(scrollable.controller!.position.maxScrollExtent, greaterThan(0));

    // スクロールバーが常時表示設定である。
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);
  });

  testWidgets('実行結果の絞り込みチェックボックスで行がフィルタリングされる', (tester) async {
    // aaa.png は成功、bbb.png は失敗になるよう設定する。
    final vm = ConvertViewModel(
      getTargetFilesUseCase: _FakeGetTargetFilesUseCase([
        '${inputDir.path}/aaa.png',
        '${inputDir.path}/bbb.png',
      ]),
      getUpscaleModelsUseCase: _FakeGetUpscaleModelsUseCase(),
      upscaleUseCase: _FakeUpscaleUseCase(),
      compressUseCase: _FakeCompressUseCase(shouldFailForBbb: true),
      processorCount: 4,
    );
    vm.setInputFolderPath(inputDir.path);
    vm.setOutputFolderPath(outputDir.path);

    await tester.pumpWidget(buildApp(vm));
    await tester.pump();
    await tester.runAsync(() => vm.runConversion());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 初期状態は全チェック済みで両ファイル表示される。
    expect(find.text('aaa.png'), findsOneWidget);
    expect(find.text('bbb.png'), findsOneWidget);

    // チェックボックスは画面下部にあり、表示されるまでスクロールする。
    // 結果表の内部スクロールではなく、画面全体のスクロールを対象にする。
    final outerScrollable = find
        .descendant(
          of: find.byType(ConvertScreen),
          matching: find.byType(Scrollable),
        )
        .first;

    // 成功チェックも外す。bbb.png は失敗(出力)だが成功(アップスケール・圧縮)も含むため、
    // 「いずれか1つでも対象を含む」という仕様に従い、成功チェックを外さないと消えない。
    await tester.scrollUntilVisible(
      find.byKey(const Key('filter_success')),
      300,
      scrollable: outerScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter_success')));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('filter_failure')),
      300,
      scrollable: outerScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter_failure')));
    await tester.pump();

    await tester.pumpAndSettle();

    // 成功・失敗・待機中のチェックを外すと、両ファイルとも表示されない。
    // (失敗したファイルは compressStatus=failure だが outputStatus=waiting のままのため、
    //   待機中チェックがONだと表示され続ける。)
    await tester.scrollUntilVisible(
      find.byKey(const Key('filter_waiting')),
      300,
      scrollable: outerScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter_waiting')));
    await tester.pump();

    expect(find.text('aaa.png'), findsNothing);
    expect(find.text('bbb.png'), findsNothing);
  });

  testWidgets('失敗チェックを外しても、いずれかの状態を含む行は表示され続ける', (tester) async {
    final vm = ConvertViewModel(
      getTargetFilesUseCase: _FakeGetTargetFilesUseCase([
        '${inputDir.path}/aaa.png',
        '${inputDir.path}/bbb.png',
      ]),
      getUpscaleModelsUseCase: _FakeGetUpscaleModelsUseCase(),
      upscaleUseCase: _FakeUpscaleUseCase(),
      compressUseCase: _FakeCompressUseCase(shouldFailForBbb: true),
      processorCount: 4,
    );
    vm.setInputFolderPath(inputDir.path);
    vm.setOutputFolderPath(outputDir.path);

    await tester.pumpWidget(buildApp(vm));
    await tester.pump();
    await tester.runAsync(() => vm.runConversion());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 待機中チェックを外しても、実行済みの行は表示されたまま(実行中/待機中が無いため)。
    // ここでは失敗チェックだけを外しても、失敗行は成功を含むので消えない点を確認するのは
    // 仕様の挙動として正しい。代わりに待機中チェックを外して「完了行のみ表示」を確認する。
    await tester.scrollUntilVisible(
      find.byKey(const Key('filter_success')),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ConvertScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter_failure')));
    await tester.pump();

    // 失敗チェックを外しても、bbb.png は成功状態(アップスケール・圧縮)と待機中(出力)を
    // 含むため、「いずれか1つでも対象を含む」仕様に従って表示され続ける。
    expect(find.text('bbb.png'), findsOneWidget);
  });
}
