"""Run with: python3 -m unittest discover -s tests -v (requires zsh and luajit)."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUA = r'''
local calls = {}
rex = {
  args = {dir=os.getenv('TEST_DIR')},
  exec = function(argv)
    calls[#calls+1] = argv
    print('CALL\t' .. table.concat(argv, '\t'))
    if argv[2] == os.getenv('MOCK_FAIL') then
      return {ok=false, stderr='injected failure'}
    end
    return {ok=true, stdout='mock'}
  end,
  json = {decode=function()
    return {session_id='test-session', initial_windows={{block_ids={'first'}}}, block_ids={'second'}}
  end}
}
local ok, result = pcall(assert(loadfile(os.getenv('HATCH_FILE'))))
if not ok then io.stderr:write(tostring(result) .. '\n'); os.exit(1) end
'''


class ScriptsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.project = self.home / 'project'
        self.project.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), ZDOTDIR=str(self.home),
                        PWD=str(self.project))

    def hatch(self, egg=None, directory=None, fail=''):
        if egg is not None:
            (self.project / '.rex-egg.lua').write_text(egg)
        env = dict(self.env, TEST_DIR=str(directory or self.project),
                   HATCH_FILE=str(ROOT / 'hatch.lua'), MOCK_FAIL=fail)
        result = subprocess.run(['luajit', '-'], input=LUA, text=True,
                                capture_output=True, env=env, timeout=5)
        calls = [line.split('\t')[1:] for line in result.stdout.splitlines()
                 if line.startswith('CALL\t')]
        return result, calls

    def test_root_directory(self):
        result, calls = self.hatch(directory='/')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[0][:5], ['rex', 'new', '/', '-c', '/'])

    def test_invalid_layouts_fail_before_creation(self):
        for egg in [
            'return {windows={{panes={{}}}}}',
            'return {windows={{}, {panes={{}, {}, {}}}}}',
            'return {windows={{panes={{}, {}}, ratio=100}}}',
            'return {windows={{panes={{}, {}}, split="diagonal"}}}',
            'return {windows={{cwd=42}}}',
            'return {windows="bad"}',
            'return 42',
            'return {windows={[2]={}}}',
        ]:
            with self.subTest(egg=egg):
                result, calls = self.hatch(egg)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [], result.stdout)

    def test_focus_and_selection_errors_propagate(self):
        for command in ['focus', 'do']:
            with self.subTest(command=command):
                result, _ = self.hatch(fail=command)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('injected failure', result.stderr)

    def test_nested_layout(self):
        egg = '''return {name="custom", windows={
          {name="code", panes={{cmd="echo hello", cwd="src"},
            {split="below", panes={{}, {cwd="/tmp"}}}}},
          {name="shell"}
        }}'''
        result, calls = self.hatch(egg)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c[1] for c in calls], ['new', 'split', 'split', 'window', 'focus', 'do'])
        self.assertIn(str(self.project / 'src'), calls[0])
        self.assertLess(calls[0].index('--json'), calls[0].index('--'))
        self.assertIn('/tmp', calls[2])

    def test_fallback_layout(self):
        config = self.home / '.config/rex'
        config.mkdir(parents=True)
        (config / '.rex-egg.lua').write_text('return {name="fallback", windows={{name="shell"}}}')
        result, calls = self.hatch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[0][2], 'fallback')

    def picker(self, fzf_status=0, find_status=0, existing=False):
        bin_dir = self.home / 'bin'
        bin_dir.mkdir(exist_ok=True)
        mocks = {
            'fzf': '#!/bin/sh\ninput=$(grep "/project$" | head -n 1)\nprintf "%s\\n" "$input"\nexit "$FZF_STATUS"\n',
            'find': '#!/bin/sh\n/usr/bin/find "$@"\nexit "$FIND_STATUS"\n',
            'rex': '#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["CALL_LOG"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\nif sys.argv[1] == "ls": print(json.dumps({"sessions": [{"label": os.environ["PROJECT_LABEL"], "session_id": "existing"}] if os.environ["EXISTING"] == "1" else []}))\n',
        }
        for name, content in mocks.items():
            path = bin_dir / name
            path.write_text(content)
            path.chmod(0o755)
        log = self.home / 'calls'
        env = dict(self.env, PATH=str(bin_dir) + ':' + os.environ['PATH'],
                   PROJECT_PICKER='fzf', FZF_STATUS=str(fzf_status),
                   FIND_STATUS=str(find_status), CALL_LOG=str(log),
                   PROJECT_LABEL='~/project', EXISTING=str(int(existing)))
        result = subprocess.run(['zsh', str(ROOT / 'pick-project.sh'), str(self.home)],
                                text=True, capture_output=True, env=env, timeout=5)
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return result, calls

    def test_installer_modes_and_preservation(self):
        bin_dir = self.home / 'bin'
        bin_dir.mkdir()
        rex = bin_dir / 'rex'
        rex.write_text('#!/bin/sh\n[ "$1 $2" = "config check" ]\n')
        rex.chmod(0o755)
        env = dict(self.env, PATH=str(bin_dir) + ':' + os.environ['PATH'])
        config = self.home / '.config/rex'
        sources = {'hatch.lua': 'hatch.lua', 'pick-project.sh': 'pick-project.sh',
                   'select-session.sh': 'select-session.sh', 'hatch-picker.lua': 'init-snippet.lua'}
        for mode in [[], ['--copy'], []]:
            result = subprocess.run(['sh', str(ROOT / 'install-local.sh'), *mode],
                                    capture_output=True, text=True, env=env, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            for target, source in sources.items():
                path = config / target
                self.assertEqual(path.is_symlink(), not mode)
                self.assertEqual(path.read_bytes(), (ROOT / source).read_bytes())
            self.assertTrue(os.access(config / 'pick-project.sh', os.X_OK))
            self.assertTrue(os.access(config / 'select-session.sh', os.X_OK))
            egg = config / '.rex-egg.lua'
            if not mode and egg.read_text() != 'custom layout':
                self.assertEqual(egg.read_bytes(), (ROOT / 'default.rex-egg.lua').read_bytes())
                egg.write_text('custom layout')
            self.assertEqual(egg.read_text(), 'custom layout')
            self.assertEqual((config / 'init.lua').read_text().count(
                'dofile(os.getenv("HOME") .. "/.config/rex/hatch-picker.lua")'), 1)

    def test_picker_cancel(self):
        for status in [1, 130]:
            result, calls = self.picker(fzf_status=status)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls, [])

    def test_picker_errors(self):
        for fzf_status, find_status in [(2, 0), (0, 1)]:
            result, calls = self.picker(fzf_status, find_status)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(calls, [])

    def test_picker_create_and_reuse(self):
        result, calls = self.picker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('dir=' + str(self.project), calls[-1])
        self.assertIn('name=~/project', calls[-1])
        result, calls = self.picker(existing=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[-1], ['do', 'session.select', 'session_id=existing'])


if __name__ == '__main__':
    unittest.main()
