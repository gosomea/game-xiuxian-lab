#!/usr/bin/env python3
"""Small positive/negative fixtures for the one-off migration content audit."""
import hashlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from audit_lfs_migration import audit


class MigrationAuditTests(unittest.TestCase):
    def command(self, root, *args, input=None):
        return subprocess.check_output(['git', '-C', str(root), *args], input=input)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='xiuxian-lfs-audit-')
        root = Path(self.temp.name)
        self.old, self.new = root / 'old', root / 'new'
        self.old.mkdir()
        self.command(self.old, 'init', '-q', '-b', 'main')
        self.command(self.old, 'config', 'user.name', 'Migration fixture')
        self.command(self.old, 'config', 'user.email', 'fixture@example.invalid')
        self.data = b'm' * 5_000_001
        (self.old / 'asset.fbx').write_bytes(self.data)
        (self.old / 'small.txt').write_text('preserve this file\n')
        self.command(self.old, 'add', '.')
        self.command(self.old, 'commit', '-q', '-m', 'fixture commit')
        self.old_head = self.command(self.old, 'rev-parse', 'HEAD').decode().strip()
        self.original_commit = self.command(self.old, 'cat-file', 'commit', self.old_head)
        self.command(root, 'clone', '-q', '--no-hardlinks', str(self.old), str(self.new))
        oid = hashlib.sha256(self.data).hexdigest()
        self.asset = self.new / '.git/lfs/objects' / oid[:2] / oid[2:4] / oid
        self.asset.parent.mkdir(parents=True)
        self.asset.write_bytes(self.data)
        (self.new / 'asset.fbx').write_text('version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize %d\n' % (oid, len(self.data)))
        self.command(self.new, 'add', 'asset.fbx')
        self.mapping = root / 'map.csv'
        self.rewrite()

    def tearDown(self):
        self.temp.cleanup()

    def rewrite(self, message=None):
        tree = self.command(self.new, 'write-tree').decode().strip()
        headers, original_message = self.original_commit.split(b'\n\n', 1)
        metadata = b'\n'.join(line for line in headers.splitlines() if not line.startswith(b'tree '))
        commit = ('tree ' + tree + '\n').encode() + metadata + b'\n\n' + (original_message if message is None else message)
        new_head = self.command(self.new, 'hash-object', '-t', 'commit', '-w', '--stdin', input=commit).decode().strip()
        self.command(self.new, 'update-ref', 'refs/heads/main', new_head)
        self.mapping.write_text(self.old_head + ',' + new_head + '\n')

    def verify(self):
        return audit(self.old / '.git', self.new / '.git', self.mapping)

    def test_content_preserved(self):
        result = self.verify()
        self.assertEqual(result['commits_checked'], 1)
        self.assertEqual(result['path_mode_content_entries_checked'], 2)
        self.assertEqual(result['unique_converted_blobs'], 1)

    def test_corrupt_asset_rejected(self):
        self.asset.write_bytes(b'x' + self.data[1:])
        with self.assertRaisesRegex(ValueError, 'SHA-256 differs'):
            self.verify()

    def test_missing_file_rejected(self):
        self.command(self.new, 'update-index', '--force-remove', 'small.txt')
        self.rewrite()
        with self.assertRaisesRegex(ValueError, 'file paths changed'):
            self.verify()

    def test_file_mode_change_rejected(self):
        self.command(self.new, 'update-index', '--chmod=+x', 'small.txt')
        self.rewrite()
        with self.assertRaisesRegex(ValueError, 'file mode changed'):
            self.verify()

    def test_message_change_rejected(self):
        self.rewrite(message=b'different message\n')
        with self.assertRaisesRegex(ValueError, 'metadata/message changed'):
            self.verify()


if __name__ == '__main__':
    unittest.main()
