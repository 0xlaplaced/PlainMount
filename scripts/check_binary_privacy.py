#!/usr/bin/env python3
"""Reject native application binaries containing builder home paths or selected private markers."""
import argparse
import json
from pathlib import Path
import re


def scan(data,markers):
    result=[]
    if re.search(rb'/(?:Users|home)/[^\x00\s]+',data): result.append('builder-home-path')
    if re.search(rb'[A-Za-z]:\\Users\\[^\\\x00\s]+',data): result.append('builder-windows-home')
    if any(value.lower() in data.lower() for value in markers): result.append('private-marker')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary',type=Path,nargs='?')
    parser.add_argument('--deny-file',type=Path)
    parser.add_argument('--self-test',action='store_true')
    args=parser.parse_args()
    if args.self_test:
        assert scan(b'/' + b'Users' + b'/example/file',[])==['builder-home-path']
        assert not scan(b'/Applications/PlainMount.app',[])
        assert scan(b'private-example',[b'private-example'])==['private-marker']
        print('3/3 binary privacy checks passed')
        return
    if args.binary is None: parser.error('binary path required')
    markers=[] if args.deny_file is None else [v.strip() for v in args.deny_file.read_bytes().splitlines() if v.strip()]
    result=scan(args.binary.read_bytes(),markers)
    print(json.dumps({'file':args.binary.name,'findings':result},indent=2))
    if result: raise SystemExit(1)

if __name__=='__main__': main()
