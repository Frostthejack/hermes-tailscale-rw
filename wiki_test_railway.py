#!/usr/bin/env python3
"""Test wiki vault clone and wiki scripts on Railway."""
import os
import subprocess
import sys
import shutil

def run(cmd, **kwargs):
    """Run a command and return output."""
    print(f"$ {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, **kwargs)
    if result.stdout:
        print(result.stdout.rstrip())
    if result.returncode != 0 and result.stderr:
        print(f"  [stderr] {result.stderr.rstrip()[:500]}")
    return result

print("=" * 60)
print("Railway Wiki Smoke Test")
print("=" * 60)

# 1. Check GITHUB_TOKEN
print("\n--- 1. GITHUB_TOKEN ---")
token = os.environ.get("GITHUB_TOKEN")
if token:
    print(f"SET ({len(token)} chars)")
else:
    print("NOT SET — cannot proceed")
    sys.exit(1)

# 2. Prerequisites
print("\n--- 2. Prerequisites ---")
run("git --version | head -1")
run("python3 --version")

# 3. Test wiki vault clone
print("\n--- 3. Wiki Vault Clone Test ---")
wiki_test = "/tmp/wiki-test-clone"
if os.path.exists(wiki_test):
    shutil.rmtree(wiki_test)

auth_url = f"http...{token}@github.com/Frostthejack/Encephalon-Mageia"
result = run(f"git clone --depth 1 '{auth_url}' '{wiki_test}'")
if result.returncode == 0:
    print("CLONE: SUCCESS")
    run(f"ls {wiki_test}/ | head -20")
    run(f"git -C {wiki_test} log --oneline -3")

    wiki_dir = os.path.join(wiki_test, "wiki")
    if os.path.isdir(wiki_dir):
        print(f"\nWiki directory contents:")
        run(f"ls {wiki_dir}/")
        # Count .md files
        md_count = 0
        for _, _, files in os.walk(wiki_dir):
            md_count += sum(1 for f in files if f.endswith('.md'))
        print(f"Wiki .md files: {md_count}")

        # Show sources.yaml if exists
        sources_path = os.path.join(wiki_dir, "sources.yaml")
        if os.path.exists(sources_path):
            print(f"\nsources.yaml found:")
            with open(sources_path) as f:
                print(f.read()[:500])
    else:
        print("WARNING: No wiki/ directory found")

    shutil.rmtree(wiki_test)
else:
    print("CLONE: FAILED")
    print("Check GITHUB_TOKEN permissions (needs repo scope)")
    shutil.rmtree(wiki_test, ignore_errors=True)
    sys.exit(1)

# 4. Test wiki-search.py
print("\n--- 4. wiki-search.py ---")
wiki_search = "/app/scripts/wiki-search.py"
if os.path.exists(wiki_search):
    print(f"FOUND: {wiki_search}")
    # Clone wiki for testing
    result = run(f"git clone --depth 1 '{auth_url}' '{wiki_test}'")
    if result.returncode == 0:
        env = os.environ.copy()
        env["WIKI_PATH"] = os.path.join(wiki_test, "wiki")
        result = subprocess.run(
            ["python3", wiki_search, "status"],
            capture_output=True, text=True, env=env
        )
        print(result.stdout.rstrip() if result.stdout else "(no stdout)")
        if result.returncode != 0:
            print(f"  (exit code {result.returncode} — Hindsight may not be running)")
        shutil.rmtree(wiki_test)
    else:
        print("Failed to clone wiki for wiki-search test")
else:
    print(f"NOT FOUND: {wiki_search}")
    run("ls /app/scripts/ 2>/dev/null || echo 'No /app/scripts/'")

# 5. Test wiki-harvester.sh
print("\n--- 5. wiki-harvester.sh ---")
harvester = "/app/wiki-harvester.sh"
if os.path.exists(harvester):
    print(f"FOUND: {harvester}")
    result = run(f"bash {harvester} --dry-run")
else:
    print(f"NOT FOUND: {harvester}")
    run("ls /app/wiki-harvester.sh* 2>/dev/null || run('ls /app/ 2>/dev/null | head -20")

print("\n" + "=" * 60)
print("=== ALL TESTS COMPLETE ===")
print("=" * 60)
