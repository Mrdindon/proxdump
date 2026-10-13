#!/usr/bin/env python3
"""Maintenance of the translations of proxdump.

    tools/i18n.py list            numbered list of the messages found in proxdump
    tools/i18n.py check           missing and obsolete entries of each lang/<code>.sh
    tools/i18n.py build CODE FILE (re)generates lang/CODE.sh from a work file

English is the source language. A message is any literal passed to the
function t in proxdump:  t "Some text with {1}" "$arg"  — as well as the
block of  t "$(cat <<'EOT' … EOT)"  and the words listed in comments of the
form  # i18n: "word" "other word"  (messages built at run time).

A work file holds one translation per message, each introduced by a line
"@@ N" where N is the number given by "list"; a message left out stays in
English. A catalogue holds one line per message:  _m $'English' $'translation'
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, 'proxdump')
LANG_DIR = os.path.join(ROOT, 'lang')


def read_dq(s, i):
    """s[i] == '"': returns (index after the closing quote, text) for a
    literal string, or (index, None) if it contains an expansion."""
    i += 1
    out, literal = '', True
    while s[i] != '"':
        c = s[i]
        if c == '\\' and s[i + 1] in '"\\$`':
            out += s[i + 1]
            i += 2
        elif c == '$' and (s[i + 1] in '({' or s[i + 1].isalpha()):
            literal = False
            # skip to the end of the string, roughly: only used to move on
            depth = 0
            while not (s[i] == '"' and depth == 0):
                if s[i] in '({':
                    depth += 1
                elif s[i] in ')}':
                    depth -= 1
                i += 1
            break
        else:
            out += c
            i += 1
    return i + 1, (out if literal else None)


def messages():
    src = open(SCRIPT, encoding='utf-8').read()
    found = []

    def add(pos, text):
        if text and text not in [m for _, m in found]:
            found.append((pos, text))

    for m in re.finditer(r'(?<![\w.-])t "', src):
        if src.startswith('"$(cat <<\'EOT\'\n', m.end() - 1):
            start = m.end() - 1 + len('"$(cat <<\'EOT\'\n')
            add(m.start(), src[start:src.index('\nEOT\n', start)])
        else:
            _, text = read_dq(src, m.end() - 1)
            add(m.start(), text)
    for m in re.finditer(r'# i18n:(.*)', src):
        for word in re.findall(r'"([^"]*)"', m.group(1)):
            add(m.start(), word)
    return [text for _, text in sorted(found)]


def ansi_c(text):
    """text -> $'…' (bash ANSI-C quoting)"""
    return "$'" + text.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n') + "'"


def un_ansi_c(s, i):
    """s[i:i+2] == "$'": returns (index after the closing quote, text)"""
    i += 2
    out = ''
    while s[i] != "'":
        if s[i] == '\\':
            out += {'n': '\n', "'": "'", '\\': '\\'}[s[i + 1]]
            i += 2
        else:
            out += s[i]
            i += 1
    return i + 1, out


def catalogue(code):
    entries = {}
    path = os.path.join(LANG_DIR, code + '.sh')
    for line in open(path, encoding='utf-8'):
        if line.startswith("_m $'"):
            i, key = un_ansi_c(line, 3)
            _, value = un_ansi_c(line, i + 1)
            entries[key] = value
    return entries


def build(code, work):
    msgs = messages()
    trans, n = {}, None
    for line in open(work, encoding='utf-8').read().split('\n'):
        m = re.fullmatch(r'@@ (\d+)', line)
        if m:
            n = int(m.group(1))
            trans[n] = []
        elif n is not None:
            trans[n].append(line)
    os.makedirs(LANG_DIR, exist_ok=True)
    path = os.path.join(LANG_DIR, code + '.sh')
    count = 0
    with open(path, 'w', encoding='utf-8') as f:
        f.write('# proxdump — translation: %s. Maintained with tools/i18n.py.\n' % code)
        f.write('# shellcheck shell=bash\n')
        for i, msg in enumerate(msgs, 1):
            if i not in trans:
                continue
            text = '\n'.join(trans[i]).strip('\n')
            if not text:
                continue
            # the placeholders of the message must all be there
            for ph in set(re.findall(r'\{\d\}', msg)):
                if ph not in text:
                    sys.exit('%s: message %d: placeholder %s is missing' % (code, i, ph))
            if msg.endswith('…') != text.endswith('…'):
                sys.exit('%s: message %d: the final … must be kept (steps are recognised by it)' % (code, i))
            f.write('_m %s %s\n' % (ansi_c(msg), ansi_c(text)))
            count += 1
    print('%s: %d of %d messages translated' % (path, count, len(msgs)))


def check():
    msgs = messages()
    status = 0
    for name in sorted(os.listdir(LANG_DIR)):
        if not name.endswith('.sh'):
            continue
        entries = catalogue(name[:-3])
        missing = [m for m in msgs if m not in entries]
        obsolete = [k for k in entries if k not in msgs]
        print('%s: %d translated, %d missing, %d obsolete' % (name, len(entries) - len(obsolete), len(missing), len(obsolete)))
        for m in missing:
            print('  missing:  %r' % m[:90])
        for k in obsolete:
            print('  obsolete: %r' % k[:90])
        if missing or obsolete:
            status = 1
    return status


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    if cmd == 'list':
        for i, msg in enumerate(messages(), 1):
            print('@@ %d' % i)
            print(msg)
    elif cmd == 'check':
        sys.exit(check())
    elif cmd == 'build' and len(sys.argv) == 4:
        build(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
