// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library fasta.testing.suite;

import 'dart:async' show Future;

import 'dart:convert' show jsonDecode;

import 'dart:io' show Directory, File, Platform;

import 'package:_fe_analyzer_shared/src/util/colors.dart' as colors;

import 'package:front_end/src/api_prototype/compiler_options.dart'
    show
        CompilerOptions,
        DiagnosticMessage,
        parseExperimentalArguments,
        parseExperimentalFlags;

import 'package:front_end/src/api_prototype/compiler_options.dart'
    show CompilerOptions, DiagnosticMessage;

import 'package:front_end/src/api_prototype/experimental_flags.dart'
    show ExperimentalFlag;

import 'package:front_end/src/api_prototype/standard_file_system.dart'
    show StandardFileSystem;

import 'package:front_end/src/base/libraries_specification.dart'
    show TargetLibrariesSpecification;

import 'package:front_end/src/base/processed_options.dart'
    show ProcessedOptions;

import 'package:front_end/src/compute_platform_binaries_location.dart'
    show computePlatformBinariesLocation;

import 'package:front_end/src/base/command_line_options.dart';

import 'package:front_end/src/fasta/compiler_context.dart' show CompilerContext;

import 'package:front_end/src/fasta/dill/dill_target.dart' show DillTarget;

import 'package:front_end/src/fasta/kernel/class_hierarchy_builder.dart'
    show ClassHierarchyNode;

import 'package:front_end/src/fasta/kernel/kernel_builder.dart'
    show ClassHierarchyBuilder;

import 'package:front_end/src/fasta/kernel/kernel_target.dart'
    show KernelTarget;

import 'package:front_end/src/fasta/ticker.dart' show Ticker;

import 'package:front_end/src/fasta/uri_translator.dart' show UriTranslator;

import 'package:kernel/ast.dart'
    show AwaitExpression, Component, Library, Node, Visitor;

import 'package:kernel/class_hierarchy.dart' show ClassHierarchy;

import 'package:kernel/core_types.dart' show CoreTypes;

import 'package:kernel/kernel.dart' show loadComponentFromBytes;

import 'package:kernel/target/targets.dart'
    show TargetFlags, DiagnosticReporter;

import 'package:testing/testing.dart'
    show
        Chain,
        ChainContext,
        Expectation,
        ExpectationSet,
        Result,
        Step,
        TestDescription,
        StdioProcess;

import 'package:vm/target/vm.dart' show VmTarget;

import '../../utils/kernel_chain.dart'
    show
        KernelTextSerialization,
        MatchContext,
        MatchExpectation,
        Print,
        TypeCheck,
        Verify,
        WriteDill;

import '../../utils/validating_instrumentation.dart'
    show ValidatingInstrumentation;

export 'package:testing/testing.dart' show Chain, runMe;

const String ENABLE_FULL_COMPILE = " full compile ";

const String EXPECTATIONS = '''
[
  {
    "name": "ExpectationFileMismatch",
    "group": "Fail"
  },
  {
    "name": "ExpectationFileMismatchSerialized",
    "group": "Fail"
  },
  {
    "name": "ExpectationFileMissing",
    "group": "Fail"
  },
  {
    "name": "InstrumentationMismatch",
    "group": "Fail"
  },
  {
    "name": "TypeCheckError",
    "group": "Fail"
  },
  {
    "name": "VerificationError",
    "group": "Fail"
  },
  {
    "name": "TransformVerificationError",
    "group": "Fail"
  },
  {
    "name": "TextSerializationFailure",
    "group": "Fail"
  }
]
''';

const String KERNEL_TEXT_SERIALIZATION = " kernel text serialization ";

final Expectation runtimeError = ExpectationSet.Default["RuntimeError"];

const String experimentalFlagOptions = '--enable-experiment=';

class TestOptions {
  final Map<ExperimentalFlag, bool> experimentalFlags;
  final bool forceLateLowering;
  final bool forceNnbdChecks;

  TestOptions(this.experimentalFlags,
      {this.forceLateLowering, this.forceNnbdChecks})
      : assert(forceLateLowering != null),
        assert(forceNnbdChecks != null);

  Map<ExperimentalFlag, bool> computeExperimentalFlags(
      Map<ExperimentalFlag, bool> forcedExperimentalFlags) {
    Map<ExperimentalFlag, bool> flags = new Map.from(experimentalFlags);
    flags.addAll(forcedExperimentalFlags);
    return flags;
  }
}

class FastaContext extends ChainContext with MatchContext {
  final UriTranslator uriTranslator;
  final List<Step> steps;
  final Uri vm;
  final bool onlyCrashes;
  final Map<ExperimentalFlag, bool> experimentalFlags;
  final bool skipVm;
  final bool verify;
  final bool weak;
  final Map<Component, KernelTarget> componentToTarget =
      <Component, KernelTarget>{};
  final Map<Component, StringBuffer> componentToDiagnostics =
      <Component, StringBuffer>{};
  final Uri platformBinaries;
  final Map<Uri, TestOptions> _testOptions = {};

  @override
  final bool updateExpectations;

  @override
  final ExpectationSet expectationSet =
      new ExpectationSet.fromJsonList(jsonDecode(EXPECTATIONS));

  Uri platformUri;

  Component platform;

  FastaContext(
      this.vm,
      this.platformBinaries,
      this.onlyCrashes,
      this.experimentalFlags,
      bool ignoreExpectations,
      this.updateExpectations,
      bool updateComments,
      this.skipVm,
      bool kernelTextSerialization,
      this.uriTranslator,
      bool fullCompile,
      this.verify,
      this.weak)
      : steps = <Step>[
          new Outline(fullCompile, updateComments: updateComments),
          const Print(),
          new Verify(fullCompile)
        ] {
    String fullPrefix;
    String outlinePrefix;
    if (weak) {
      fullPrefix = '.weak';
      outlinePrefix = '.weak.outline';
    } else {
      fullPrefix = '.strong';
      outlinePrefix = '.outline';
    }
    if (!ignoreExpectations) {
      steps.add(new MatchExpectation(
          fullCompile ? "$fullPrefix.expect" : "$outlinePrefix.expect",
          serializeFirst: false));
      if (!updateExpectations) {
        steps.add(new MatchExpectation(
            fullCompile ? "$fullPrefix.expect" : "$outlinePrefix.expect",
            serializeFirst: true));
      }
    }
    steps.add(const TypeCheck());
    steps.add(const EnsureNoErrors());
    if (kernelTextSerialization) {
      steps.add(const KernelTextSerialization());
    }
    if (fullCompile) {
      steps.add(const Transform());
      if (!ignoreExpectations) {
        steps.add(new MatchExpectation(
            fullCompile
                ? "$fullPrefix.transformed.expect"
                : "$outlinePrefix.transformed.expect",
            serializeFirst: false));
        if (!updateExpectations) {
          steps.add(new MatchExpectation(
              fullCompile
                  ? "$fullPrefix.transformed.expect"
                  : "$outlinePrefix.transformed.expect",
              serializeFirst: true));
        }
      }
      steps.add(const EnsureNoErrors());
      if (!skipVm) {
        steps.add(const WriteDill());
        steps.add(const Run());
      }
    }
  }

  /// Computes the experimental flag for [description].
  ///
  /// [forcedExperimentalFlags] is used to override the default flags for
  /// [description].
  TestOptions computeTestOptions(TestDescription description) {
    Directory directory = new File.fromUri(description.uri).parent;
    // TODO(johnniwinther): Support nested test folders?
    TestOptions testOptions = _testOptions[directory.uri];
    if (testOptions == null) {
      bool forceLateLowering = false;
      bool forceNnbdChecks = false;
      List<String> experimentalFlagsArguments = [];
      File optionsFile =
          new File.fromUri(directory.uri.resolve('test.options'));
      if (optionsFile.existsSync()) {
        for (String line in optionsFile.readAsStringSync().split('\n')) {
          line = line.trim();
          if (line.startsWith(experimentalFlagOptions)) {
            experimentalFlagsArguments =
                line.substring(experimentalFlagOptions.length).split('\n');
          } else if (line.startsWith(Flags.forceLateLowering)) {
            forceLateLowering = true;
          } else if (line.startsWith(Flags.forceNnbdChecks)) {
            forceNnbdChecks = true;
          } else if (line.isNotEmpty) {
            throw new UnsupportedError("Unsupported test option '$line'");
          }
        }
      }
      testOptions = new TestOptions(
          parseExperimentalFlags(
              parseExperimentalArguments(experimentalFlagsArguments),
              onError: (String message) => throw new ArgumentError(message),
              onWarning: (String message) => throw new ArgumentError(message)),
          forceLateLowering: forceLateLowering,
          forceNnbdChecks: forceNnbdChecks);
      _testOptions[directory.uri] = testOptions;
    }
    return testOptions;
  }

  Expectation get verificationError => expectationSet["VerificationError"];

  Future ensurePlatformUris() async {
    if (platformUri == null) {
      platformUri = platformBinaries.resolve("vm_platform_strong.dill");
    }
  }

  Future<Component> loadPlatform() async {
    if (platform == null) {
      await ensurePlatformUris();
      platform = loadComponentFromBytes(
          new File.fromUri(platformUri).readAsBytesSync());
    }
    return platform;
  }

  @override
  Result processTestResult(
      TestDescription description, Result result, bool last) {
    if (onlyCrashes) {
      Expectation outcome = result.outcome;
      if (outcome == Expectation.Crash || outcome == verificationError) {
        return result;
      }
      return result.copyWithOutcome(Expectation.Pass);
    }
    return super.processTestResult(description, result, last);
  }

  @override
  Set<Expectation> processExpectedOutcomes(Set<Expectation> outcomes) {
    if (skipVm && outcomes.length == 1 && outcomes.single == runtimeError) {
      return new Set<Expectation>.from([Expectation.Pass]);
    } else {
      return outcomes;
    }
  }

  static Future<FastaContext> create(
      Chain suite, Map<String, String> environment) async {
    Uri sdk = Uri.base.resolve("sdk/");
    Uri vm = Uri.base.resolveUri(new Uri.file(Platform.resolvedExecutable));
    Uri packages = Uri.base.resolve(".packages");
    Map<ExperimentalFlag, bool> experimentalFlags = <ExperimentalFlag, bool>{};

    void addForcedExperimentalFlag(String name, ExperimentalFlag flag) {
      if (environment.containsKey(name)) {
        experimentalFlags[flag] = environment[name] == "true";
      }
    }

    addForcedExperimentalFlag(
        "enableExtensionMethods", ExperimentalFlag.extensionMethods);
    addForcedExperimentalFlag(
        "enableNonNullable", ExperimentalFlag.nonNullable);

    bool weak = environment["weak"] == "true";
    var options = new ProcessedOptions(
        options: new CompilerOptions()
          ..onDiagnostic = (DiagnosticMessage message) {
            throw message.plainTextFormatted.join("\n");
          }
          ..sdkRoot = sdk
          ..packagesFileUri = packages
          ..environmentDefines = {}
          ..experimentalFlags = experimentalFlags
          ..nnbdStrongMode = !weak);
    UriTranslator uriTranslator = await options.getUriTranslator();
    bool onlyCrashes = environment["onlyCrashes"] == "true";
    bool ignoreExpectations = environment["ignoreExpectations"] == "true";
    bool updateExpectations = environment["updateExpectations"] == "true";
    bool updateComments = environment["updateComments"] == "true";
    bool skipVm = environment["skipVm"] == "true";
    bool verify = environment["verify"] != "false";
    bool kernelTextSerialization =
        environment.containsKey(KERNEL_TEXT_SERIALIZATION);
    String platformBinaries = environment["platformBinaries"];
    if (platformBinaries != null && !platformBinaries.endsWith('/')) {
      platformBinaries = '$platformBinaries/';
    }
    return new FastaContext(
        vm,
        platformBinaries == null
            ? computePlatformBinariesLocation(forceBuildDir: true)
            : Uri.base.resolve(platformBinaries),
        onlyCrashes,
        experimentalFlags,
        ignoreExpectations,
        updateExpectations,
        updateComments,
        skipVm,
        kernelTextSerialization,
        uriTranslator,
        environment.containsKey(ENABLE_FULL_COMPILE),
        verify,
        weak);
  }
}

class Run extends Step<Uri, int, FastaContext> {
  const Run();

  String get name => "run";

  bool get isAsync => true;

  bool get isRuntime => true;

  Future<Result<int>> run(Uri uri, FastaContext context) async {
    if (context.platformUri == null) {
      throw "Executed `Run` step before initializing the context.";
    }
    File generated = new File.fromUri(uri);
    StdioProcess process;
    try {
      var args = <String>[];
      args.add(generated.path);
      process = await StdioProcess.run(context.vm.toFilePath(), args);
      print(process.output);
    } finally {
      await generated.parent.delete(recursive: true);
    }
    return process.toResult();
  }
}

class Outline extends Step<TestDescription, Component, FastaContext> {
  final bool fullCompile;

  const Outline(this.fullCompile, {this.updateComments: false});

  final bool updateComments;

  String get name {
    return fullCompile ? "compile" : "outline";
  }

  bool get isCompiler => fullCompile;

  Future<Result<Component>> run(
      TestDescription description, FastaContext context) async {
    StringBuffer errors = new StringBuffer();
    TestOptions testOptions = context.computeTestOptions(description);
    ProcessedOptions options = new ProcessedOptions(
        options: new CompilerOptions()
          ..onDiagnostic = (DiagnosticMessage message) {
            if (errors.isNotEmpty) {
              errors.write("\n\n");
            }
            errors.writeAll(message.plainTextFormatted, "\n");
          }
          ..environmentDefines = {}
          ..experimentalFlags =
              testOptions.computeExperimentalFlags(context.experimentalFlags)
          ..performNnbdChecks = testOptions.forceNnbdChecks
          ..nnbdStrongMode = !context.weak,
        inputs: <Uri>[description.uri]);
    return await CompilerContext.runWithOptions(options, (_) async {
      // Disable colors to ensure that expectation files are the same across
      // platforms and independent of stdin/stderr.
      colors.enableColors = false;
      Component platform = await context.loadPlatform();
      Ticker ticker = new Ticker();
      DillTarget dillTarget = new DillTarget(
        ticker,
        context.uriTranslator,
        new TestVmTarget(new TargetFlags(
            forceLateLoweringForTesting: testOptions.forceLateLowering)),
      );
      dillTarget.loader.appendLibraries(platform);
      // We create a new URI translator to avoid reading platform libraries from
      // file system.
      UriTranslator uriTranslator = new UriTranslator(
          const TargetLibrariesSpecification('vm'),
          context.uriTranslator.packages);
      KernelTarget sourceTarget = new KernelTarget(
          StandardFileSystem.instance, false, dillTarget, uriTranslator);

      sourceTarget.setEntryPoints(<Uri>[description.uri]);
      await dillTarget.buildOutlines();
      ValidatingInstrumentation instrumentation;
      instrumentation = new ValidatingInstrumentation();
      await instrumentation.loadExpectations(description.uri);
      sourceTarget.loader.instrumentation = instrumentation;
      Component p = await sourceTarget.buildOutlines();
      context.componentToTarget.clear();
      context.componentToTarget[p] = sourceTarget;
      context.componentToDiagnostics.clear();
      context.componentToDiagnostics[p] = errors;
      if (fullCompile) {
        p = await sourceTarget.buildComponent(verify: context.verify);
        instrumentation?.finish();
        if (instrumentation != null && instrumentation.hasProblems) {
          if (updateComments) {
            await instrumentation.fixSource(description.uri, false);
          } else {
            return new Result<Component>(
                p,
                context.expectationSet["InstrumentationMismatch"],
                instrumentation.problemsAsString,
                null);
          }
        }
      }
      return pass(p);
    });
  }
}

class Transform extends Step<Component, Component, FastaContext> {
  const Transform();

  String get name => "transform component";

  Future<Result<Component>> run(
      Component component, FastaContext context) async {
    KernelTarget sourceTarget = context.componentToTarget[component];
    context.componentToTarget.remove(component);
    TestVmTarget backendTarget = sourceTarget.backendTarget;
    backendTarget.enabled = true;
    try {
      if (sourceTarget.loader.coreTypes != null) {
        sourceTarget.runBuildTransformations();
      }
    } finally {
      backendTarget.enabled = false;
    }
    List<String> errors = VerifyTransformed.verify(component);
    if (errors.isNotEmpty) {
      return new Result<Component>(
          component,
          context.expectationSet["TransformVerificationError"],
          errors.join('\n'),
          null);
    }
    return pass(component);
  }
}

/// Visitor that checks that the component has been transformed properly.
// TODO(johnniwinther): Add checks for all nodes that are unsupported after
// transformation.
class VerifyTransformed extends Visitor<void> {
  List<String> errors = [];

  @override
  void defaultNode(Node node) {
    node.visitChildren(this);
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    errors.add("ERROR: Untransformed await expression: $node");
  }

  static List<String> verify(Component component) {
    VerifyTransformed visitor = new VerifyTransformed();
    component.accept(visitor);
    return visitor.errors;
  }
}

class TestVmTarget extends VmTarget {
  bool enabled = false;

  TestVmTarget(TargetFlags flags) : super(flags);

  String get name => "vm";

  @override
  void performModularTransformationsOnLibraries(
      Component component,
      CoreTypes coreTypes,
      ClassHierarchy hierarchy,
      List<Library> libraries,
      Map<String, String> environmentDefines,
      DiagnosticReporter diagnosticReporter,
      {void logger(String msg)}) {
    if (enabled) {
      super.performModularTransformationsOnLibraries(component, coreTypes,
          hierarchy, libraries, environmentDefines, diagnosticReporter,
          logger: logger);
    }
  }
}

class EnsureNoErrors extends Step<Component, Component, FastaContext> {
  const EnsureNoErrors();

  String get name => "check errors";

  Future<Result<Component>> run(
      Component component, FastaContext context) async {
    StringBuffer buffer = context.componentToDiagnostics[component];
    return buffer.isEmpty
        ? pass(component)
        : fail(component, """Unexpected errors:\n$buffer""");
  }
}

class MatchHierarchy extends Step<Component, Component, FastaContext> {
  const MatchHierarchy();

  String get name => "check hierarchy";

  Future<Result<Component>> run(
      Component component, FastaContext context) async {
    Uri uri =
        component.uriToSource.keys.firstWhere((uri) => uri?.scheme == "file");
    KernelTarget target = context.componentToTarget[component];
    ClassHierarchyBuilder hierarchy = target.loader.builderHierarchy;
    StringBuffer sb = new StringBuffer();
    for (ClassHierarchyNode node in hierarchy.nodes.values) {
      sb.writeln(node);
    }
    return context.match<Component>(".hierarchy.expect", "$sb", uri, component);
  }
}
