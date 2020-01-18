#!/usr/bin/env python
#
# Copyright 2013 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
""" Builds all Fuchsia artifacts vended by Flutter.
"""

import argparse
import errno
import os
import platform
import shutil
import subprocess
import sys
import tempfile

from gather_flutter_runner_artifacts import CreateMetaPackage, CopyPath
from gen_package import CreateFarPackage

_script_dir = os.path.abspath(os.path.join(os.path.realpath(__file__), '..'))
_src_root_dir = os.path.join(_script_dir, '..', '..', '..')
_out_dir = os.path.join(_src_root_dir, 'out')
_bucket_directory = os.path.join(_out_dir, 'fuchsia_bucket')
_fuchsia_base = 'flutter/shell/platform/fuchsia'


def IsLinux():
  return platform.system() == 'Linux'


def IsMac():
  return platform.system() == 'Darwin'


def GetPMBinPath():
  # host_os references the gn host_os
  # https://gn.googlesource.com/gn/+/master/docs/reference.md#var_host_os
  host_os = ''
  if IsLinux():
    host_os = 'linux'
  elif IsMac():
    host_os = 'mac'
  else:
    host_os = 'windows'

  return os.path.join(_src_root_dir, 'fuchsia', 'sdk', host_os, 'tools', 'pm')


def RunExecutable(command):
  subprocess.check_call(command, cwd=_src_root_dir)


def RunGN(variant_dir, flags):
  print('Running gn for variant "%s" with flags: %s' %
        (variant_dir, ','.join(flags)))
  RunExecutable([
      os.path.join('flutter', 'tools', 'gn'),
  ] + flags)

  assert os.path.exists(os.path.join(_out_dir, variant_dir))


def BuildNinjaTargets(variant_dir, targets):
  assert os.path.exists(os.path.join(_out_dir, variant_dir))

  RunExecutable(['autoninja', '-C',
                 os.path.join(_out_dir, variant_dir)] + targets)


def RemoveDirectoryIfExists(path):
  if not os.path.exists(path):
    return

  if os.path.isfile(path) or os.path.islink(path):
    os.unlink(path)
  else:
    shutil.rmtree(path)


def CopyFiles(source, destination):
  try:
    shutil.copytree(source, destination)
  except OSError as error:
    if error.errno == errno.ENOTDIR:
      shutil.copy(source, destination)
    else:
      raise


def FindFile(name, path):
  for root, dirs, files in os.walk(path):
    if name in files:
      return os.path.join(root, name)


def FindFileAndCopyTo(file_name, source, dest_parent, dst_name=None):
  found = FindFile(file_name, source)
  if not dst_name:
    dst_name = file_name
  if found:
    dst_path = os.path.join(dest_parent, dst_name)
    CopyPath(found, dst_path)


def CopyGenSnapshotIfExists(source, destination):
  source_root = os.path.join(_out_dir, source)
  destination_base = os.path.join(destination, 'dart_binaries')
  FindFileAndCopyTo('gen_snapshot', source_root, destination_base)
  FindFileAndCopyTo('gen_snapshot_product', source_root, destination_base)
  FindFileAndCopyTo('kernel_compiler.dart.snapshot', source_root,
                    destination_base, 'kernel_compiler.snapshot')
  FindFileAndCopyTo('frontend_server.dart.snapshot', source_root,
                    destination_base, 'flutter_frontend_server.snapshot')


def CopyFlutterTesterBinIfExists(source, destination):
  source_root = os.path.join(_out_dir, source)
  destination_base = os.path.join(destination, 'flutter_binaries')
  FindFileAndCopyTo('flutter_tester', source_root, destination_base)


def CopyToBucketWithMode(source, destination, aot, product, runner_type):
  mode = 'aot' if aot else 'jit'
  product_suff = '_product' if product else ''
  runner_name = '%s_%s%s_runner' % (runner_type, mode, product_suff)
  far_dir_name = '%s_far' % runner_name
  source_root = os.path.join(_out_dir, source)
  far_base = os.path.join(source_root, far_dir_name)
  CreateMetaPackage(far_base, runner_name)
  pm_bin = GetPMBinPath()
  key_path = os.path.join(_script_dir, 'development.key')

  destination = os.path.join(_bucket_directory, destination, mode)
  CreateFarPackage(pm_bin, far_base, key_path, destination)
  patched_sdk_dirname = '%s_runner_patched_sdk' % runner_type
  patched_sdk_dir = os.path.join(source_root, patched_sdk_dirname)
  dest_sdk_path = os.path.join(destination, patched_sdk_dirname)
  if not os.path.exists(dest_sdk_path):
    CopyPath(patched_sdk_dir, dest_sdk_path)
  CopyGenSnapshotIfExists(source_root, destination)
  CopyFlutterTesterBinIfExists(source_root, destination)


def CopyToBucket(src, dst, product=False):
  CopyToBucketWithMode(src, dst, False, product, 'flutter')
  CopyToBucketWithMode(src, dst, True, product, 'flutter')
  CopyToBucketWithMode(src, dst, False, product, 'dart')
  CopyToBucketWithMode(src, dst, True, product, 'dart')


def BuildBucket(runtime_mode, arch, product):
  out_dir = 'fuchsia_%s_%s/' % (runtime_mode, arch)
  bucket_dir = 'flutter/%s/%s/' % (arch, runtime_mode)
  CopyToBucket(out_dir, bucket_dir, product)


def ProcessCIPDPackage(upload, engine_version):
  # Copy the CIPD YAML template from the source directory to be next to the bucket
  # we are about to package.
  cipd_yaml = os.path.join(_script_dir, 'fuchsia.cipd.yaml')
  CopyFiles(cipd_yaml, os.path.join(_bucket_directory, 'fuchsia.cipd.yaml'))

  if upload and IsLinux():
    command = [
        'cipd', 'create', '-pkg-def', 'fuchsia.cipd.yaml', '-ref', 'latest',
        '-tag',
        'git_revision:%s' % engine_version
    ]
  else:
    command = [
        'cipd', 'pkg-build', '-pkg-def', 'fuchsia.cipd.yaml', '-out',
        os.path.join(_bucket_directory, 'fuchsia.cipd')
    ]

  subprocess.check_call(command, cwd=_bucket_directory)


def GetRunnerTarget(runner_type, product, aot):
  base = '%s/%s:' % (_fuchsia_base, runner_type)
  if 'dart' in runner_type:
    target = 'dart_'
  else:
    target = 'flutter_'
  if aot:
    target += 'aot_'
  else:
    target += 'jit_'
  if product:
    target += 'product_'
  target += 'runner'
  return base + target


def GetTargetsToBuild(product=False):
  targets_to_build = [
      'flutter/shell/platform/fuchsia:fuchsia',
  ]
  return targets_to_build


def BuildTarget(runtime_mode, arch, product, enable_lto):
  out_dir = 'fuchsia_%s_%s' % (runtime_mode, arch)
  flags = [
      '--fuchsia',
      '--fuchsia-cpu',
      arch,
      '--runtime-mode',
      runtime_mode,
  ]

  # Always disable lto until https://github.com/flutter/flutter/issues/44841
  # gets fixed.
  # if not enable_lto:
  flags.append('--no-lto')

  RunGN(out_dir, flags)
  BuildNinjaTargets(out_dir, GetTargetsToBuild(product))

  return


def main():
  parser = argparse.ArgumentParser()

  parser.add_argument(
      '--upload',
      default=False,
      action='store_true',
      help='If set, uploads the CIPD package and tags it as the latest.')

  parser.add_argument(
      '--engine-version',
      required=False,
      help='Specifies the flutter engine SHA.')

  parser.add_argument(
      '--runtime-mode',
      type=str,
      choices=['debug', 'profile', 'release', 'all'],
      default='all')

  parser.add_argument(
      '--archs', type=str, choices=['x64', 'arm64', 'all'], default='all')

  parser.add_argument(
      '--no-lto',
      action='store_true',
      default=False,
      help='If set, disables LTO for the build.')

  parser.add_argument(
      '--skip-build',
      action='store_true',
      default=False,
      help='If set, skips building and just creates packages.')

  args = parser.parse_args()
  RemoveDirectoryIfExists(_bucket_directory)
  build_mode = args.runtime_mode

  archs = ['x64', 'arm64'] if args.archs == 'all' else [args.archs]
  runtime_modes = ['debug', 'profile', 'release']
  product_modes = [False, False, True]

  enable_lto = not args.no_lto

  for arch in archs:
    for i in range(3):
      runtime_mode = runtime_modes[i]
      product = product_modes[i]
      if build_mode == 'all' or runtime_mode == build_mode:
        if not args.skip_build:
          BuildTarget(runtime_mode, arch, product, enable_lto)
        BuildBucket(runtime_mode, arch, product)

  if args.upload:
    if args.engine_version is None:
      print('--upload requires --engine-version to be specified.')
      return 1
    ProcessCIPDPackage(args.upload, args.engine_version)
  return 0


if __name__ == '__main__':
  sys.exit(main())
