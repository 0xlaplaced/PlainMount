#!/usr/bin/env python3
"""Check the staged payload without printing matched values or line contents."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

RULES = {
    'home-directory': rb"/(?:Users|home)/[^\s/'\"<>]+",
    'windows-home': rb"[A-Za-z]:\\Users\\[^\\\s]+",
    'private-key': rb"-----BEGIN[ A-Z]*PRIVATE KEY-----",
    'github-token': rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b",
    'api-token': rb"\bsk-(?:proj-)?[A-Za-z0-9_-]{24,}\b",
    'aws-key': rb"\bAKIA[0-9A-Z]{16}\b",
    'secret-assignment': rb"(?i)\b(?:api[_-]?key|private[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*['\"][^'\"\r\n]{8,}['\"]",
    'chat-id': rb"\b01[a-f0-9]{6}-[a-f0-9-]{25,}\b",
    'hardware-registry-snapshot': rb"IOService:" + rb"/",
}
BLOCKED_PARTS = {'.build', 'dist', '.local-backend', 'work', 'outputs', '__pycache__'}
BLOCKED_SUFFIXES = {'.p12', '.pfx', '.key', '.pem', '.mobileprovision', '.log', '.zip', '.pkg', '.dmg', '.dylib', '.tgz'}

def findings(path, data, markers):
    result=[]
    value=Path(path)
    if any(part in BLOCKED_PARTS or part.startswith('.env') for part in value.parts) or value.suffix.lower() in BLOCKED_SUFFIXES:
        result.append('excluded-file')
    if b'\0' in data:
        result.append('binary-file')
    for name, pattern in RULES.items():
        if re.search(pattern, data): result.append(name)
    lower=data.lower()
    if any(marker.lower() in lower for marker in markers): result.append('private-marker')
    return sorted(set(result))

def self_test():
    cases=[
        ('sample.txt', b'/' + b'Users' + b'/example/file', True),
        ('sample.txt', b'gh' + b'p_' + b'x'*36, True),
        ('sample.txt', b'-----BEGIN ' + b'PRIVATE KEY-----', True),
        ('sample.txt', b'api_' + b'key = "' + b'x'*20 + b'"', True),
        ('.env.local', b'empty', True),
        ('runtime.dylib', b'fake-runtime', True),
        ('sample.txt', b'bytes\0bytes', True),
        ('Sources/Sample.swift', b'let path = "/Applications/PlainMount.app"', False),
        ('README.md', b'# PlainMount\nNo personal diagnostics are distributed.', False),
    ]
    for path,data,expected in cases:
        if bool(findings(path,data,[])) != expected: raise AssertionError('Privacy self-test failed')
    print(str(len(cases))+'/'+str(len(cases))+' privacy checks passed')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged',action='store_true')
    parser.add_argument('--deny-file',type=Path)
    parser.add_argument('--self-test',action='store_true')
    args=parser.parse_args()
    if args.self_test: self_test(); return
    markers=[] if args.deny_file is None else [row.strip() for row in args.deny_file.read_bytes().splitlines() if row.strip()]
    paths=subprocess.check_output(['git','ls-files','-z']).split(b'\0')
    paths=[p.decode() for p in paths if p]
    if not paths: raise SystemExit('No tracked payload to verify')
    output=[]
    for path in paths:
        mode=subprocess.check_output(['git','ls-files','--stage','--',path]).split(maxsplit=1)[0]
        if mode==b'120000':
            output.append({'path':path,'rule':'symlink'}); continue
        data=subprocess.check_output(['git','show',':'+path]) if args.staged else Path(path).read_bytes()
        output.extend({'path':path,'rule':rule} for rule in findings(path,data,markers))
    print(json.dumps({'files_scanned':len(paths),'findings':output},indent=2))
    if output: raise SystemExit(1)

if __name__=='__main__': main()
