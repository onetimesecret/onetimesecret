#!/usr/bin/env python3
"""Turn on the scheduled jobs that are off by default and shorten their
schedules, in an etc/config.yaml (ERB + YAML, so edited as text). Only keys
under `jobs:` are touched. This is operator configuration, not a code change:
the same edit is applied to HEAD's config and to v0.26.19's own config."""
import re
import sys

path = sys.argv[1]
SET = {
    ('jobs', 'expiration_warnings', 'enabled'): 'true',
    ('jobs', 'expiration_warnings', 'check_interval'): "'1m'",
    ('jobs', 'expiration_warnings', 'warning_hours'): '200',
    ('jobs', 'maintenance', 'enabled'): 'true',
}
for job in ('phantom_cleanup', 'data_audit', 'participation_gc', 'index_rebuild', 'instances_rebuild', 'housekeeping'):
    SET[('jobs', 'maintenance', job, 'enabled')] = 'true'
    SET[('jobs', 'maintenance', job, 'interval')] = "'2m'"
    SET[('jobs', 'maintenance', job, 'cron')] = "'*/2 * * * *'"
    SET[('jobs', 'maintenance', job, 'auto_repair')] = 'true'

out, stack, changed = [], [], 0
for line in open(path):
    m = re.match(r'^(\s*)([A-Za-z_][A-Za-z0-9_]*):(\s*)(.*?)(\s+#.*)?$', line.rstrip('\n'))
    if m and not line.lstrip().startswith('#'):
        indent = len(m.group(1))
        while stack and stack[-1][0] >= indent:
            stack.pop()
        stack.append((indent, m.group(2)))
        key = tuple(k for _, k in stack)
        if key in SET and m.group(4) != '':
            line = f"{m.group(1)}{m.group(2)}: {SET[key]}{m.group(5) or ''}\n"
            changed += 1
    out.append(line)
open(path, 'w').writelines(out)
print(f'{path}: {changed} keys set')
