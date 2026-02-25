import sys

path = r'd:\Jouri\lib\features\trips\trip_detail_page.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if line.startswith('                          onPressed: () async {'):
        new_lines.append('                          onPressed: _downloadAllMedia,\n')
        skip = True
    elif skip and line.startswith('                          },'):
        skip = False
    elif not skip:
        new_lines.append(line)

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

