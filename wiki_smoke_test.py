#!/usr/bin/env python3
import os, subprocess, sys, shutil

print("Railway Wiki Smoke Test")

token = os.environ.get("GITHUB_TOKEN")
if not token:
    print("GITHUB_TOKEN: NOT SET")
    sys.exit(1)
print(f"GITHUB_TOKEN: SET ({len(token)} chars)")

for cmd in ["git --version", "python3 --version"]:
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    line = r.stdout.splitlines()[0] if r.stdout else "N/A"
    print(f"  {cmd}: {line}")

print("Wiki Vault Clone Test")
wiki_test = "/tmp/wiki-test-clone"
if os.path.exists(wiki_test):
    shutil.rmtree(wiki_test)

auth_url = "https://x-access-token:" + token + "@github.com/Frostthejack/Encephalon-Mageia"
result = subprocess.run("git clone --depth 1 " + auth_url + " " + wiki_test, shell=True, capture_output=True, text=True)
if result.returncode == 0:
    print("CLONE: SUCCESS")
    r = subprocess.run("ls " + wiki_test + "/", shell=True, capture_output=True, text=True)
    print(r.stdout)
    wiki_dir = os.path.join(wiki_test, "wiki")
    if os.path.isdir(wiki_dir):
        r = subprocess.run("ls " + wiki_dir + "/", shell=True, capture_output=True, text=True)
        print("Wiki dir:")
        print(r.stdout)
    shutil.rmtree(wiki_test)
else:
    print("CLONE: FAILED")
    print(result.stderr[:500])
    shutil.rmtree(wiki_test, ignore_errors=True)

wp = "/app/scripts/wiki-search.py"
if os.path.exists(wp):
    print("wiki-search.py: FOUND at " + wp)
else:
    print("wiki-search.py: NOT FOUND at " + wp)

wh = "/app/wiki-harvester.sh"
if os.path.exists(wh):
    print("wiki-harvester.sh: FOUND at " + wh)
    r = subprocess.run("bash " + wh + " --dry-run", shell=True, capture_output=True, text=True)
    print(r.stdout)
    if r.stderr:
        print("stderr:", r.stderr[:300])
else:
    print("wiki-harvester.sh: NOT FOUND at " + wh)

print("Wiki git-sync.sh:")
wg = "/app/wiki-git-sync.sh"
if os.path.exists(wg):
    print("  FOUND at " + wg)
else:
    print("  NOT FOUND at " + wg)

print("COMPLETE")
