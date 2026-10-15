#!/usr/bin/env python3
"""Regenerates the permission table in docs/security/role-permission-matrix.md
from lib/core/permissions/role_permissions.dart (the single UI-side source of
truth). Run: python3 tool/gen_permission_matrix.py > /tmp/table.md"""
import re, sys
s = open('lib/core/permissions/role_permissions.dart').read()
roles = {}
for m in re.finditer(r'UserRole\.(\w+): \{(.*?)\n    \},', s, re.S):
    roles[m.group(1)] = set(re.findall(r'Permission\.(\w+)', m.group(2)))
order = ['platformAdmin', 'schoolAdmin', 'branchAdmin', 'finance', 'teacher', 'parent']
heads = ['Platform', 'School admin', 'Branch admin', 'Finance', 'Teacher', 'Parent']
allp = sorted(set().union(*roles.values()))
print('| Permission | ' + ' | '.join(heads) + ' |')
print('|---|' + '---|' * len(order))
for p in allp:
    print(f'| `{p}` | ' + ' | '.join('✔' if p in roles[r] else '' for r in order) + ' |')
