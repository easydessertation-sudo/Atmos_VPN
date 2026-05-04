import ast
import os

base = r'd:\vaavix\VPN\vpn\vpn-admin-panel'
files = []
for root, dirs, fnames in os.walk(base):
    dirs[:] = [d for d in dirs if d not in ['venv', '__pycache__']]
    for f in fnames:
        if f.endswith('.py'):
            files.append(os.path.join(root, f))

files.sort()
errors = []
for fp in files:
    try:
        with open(fp, 'r', encoding='utf-8') as fh:
            src = fh.read()
        ast.parse(src)
        rel = fp.replace(base, '')
        print(f'  OK  {rel}')
    except SyntaxError as e:
        errors.append((fp, e))
        print(f'  ERR {fp}: {e}')

print()
if not errors:
    print('All files passed syntax check!')
else:
    print(f'{len(errors)} file(s) have errors.')
