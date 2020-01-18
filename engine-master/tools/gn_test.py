# Copyright 2013 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
import unittest

import os
import imp
SKY_TOOLS = os.path.dirname(os.path.abspath(__file__))
gn = imp.load_source('gn', os.path.join(SKY_TOOLS, 'gn'))


class GNTestCase(unittest.TestCase):
    def _expect_build_dir(self, arg_list, expected_build_dir):
        args = gn.parse_args(['gn'] + arg_list)
        self.assertEquals(gn.get_out_dir(args), expected_build_dir)

    def test_get_out_dir(self):
        self._expect_build_dir(['--debug'], 'out/Debug')
        self._expect_build_dir(['--release'], 'out/Release')
        self._expect_build_dir(['--ios'], 'out/ios_Debug')
        self._expect_build_dir(['--ios', '--release'], 'out/ios_Release')
        self._expect_build_dir(['--android'], 'out/android_Debug')
        self._expect_build_dir(['--android', '--release'], 'out/android_Release')

    def _gn_args(self, arg_list):
        args = gn.parse_args(['gn'] + arg_list)
        return gn.to_gn_args(args)

    def test_to_gn_args(self):
        # This would not necessarily be true on a 32-bit machine?
        self.assertEquals(self._gn_args(['--ios', '--simulator'])['target_cpu'], 'x64')
        self.assertEquals(self._gn_args(['--ios'])['target_cpu'], 'arm')


if __name__ == '__main__':
    unittest.main()
