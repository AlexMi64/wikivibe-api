#!/usr/bin/env python3
"""Publish immutable versioned assets, then advance the signed Sparkle feed."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

REPOSITORY = "AlexMi64/wikivibe-api"
FEED_TAG = "update-feed"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
TOOLS = Path("build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin")


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def release(tag):
    result = subprocess.run(["gh", "api", f"repos/{REPOSITORY}/releases/tags/{tag}"], capture_output=True, text=True)
    if result.returncode == 0:
        return json.loads(result.stdout)
    if "HTTP 404" in result.stderr:
        return None
    raise RuntimeError("Could not query release metadata; refusing to publish")


def version():
    source = Path("project.yml").read_text()
    build = re.search(r'^    CURRENT_PROJECT_VERSION: "([0-9]+)"$', source, re.M).group(1)
    marketing = re.search(r'^    MARKETING_VERSION: "([0-9.]+)"$', source, re.M).group(1)
    return build, marketing, f"v{marketing}-preview.{build}"


def download(tag, name, directory):
    directory.mkdir(parents=True, exist_ok=True)
    run("gh", "release", "download", tag, "--repo", REPOSITORY,
        "--pattern", name, "--dir", str(directory), "--clobber")
    return directory / name


def feed_version(path):
    versions = [int(node.text) for node in ET.parse(path).getroot().findall(f"./channel/item/{{{SPARKLE}}}version")]
    if not versions:
        raise RuntimeError("Update feed contains no version; refusing to replace it")
    return max(versions)


def current_feed_version():
    if release(FEED_TAG) is None:
        return 0
    return feed_version(download(FEED_TAG, "appcast.xml", Path("build/previous-feed")))


def plan():
    build, _, tag = version()
    previous = current_feed_version()
    existing = release(tag)
    publish = previous < int(build)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"publish={str(publish).lower()}\nbuild_required={str(publish and existing is None).lower()}\nbuild={build}\ntag={tag}\n")
    print(f"Build {build}; channel {previous}; {'publish/resume' if publish else 'already covered'}")


def verify(appcast, dmg, build, secret):
    run(str(TOOLS / "sign_update"), "--ed-key-file", "-", "--verify", str(appcast), input=secret + "\n", text=True)
    item = ET.parse(appcast).getroot().find("./channel/item")
    if item is None or item.findtext(f"{{{SPARKLE}}}version") != build:
        raise RuntimeError("Feed version does not match the requested build")
    enclosure = item.find("enclosure")
    signature = enclosure.get(f"{{{SPARKLE}}}edSignature") if enclosure is not None else None
    if not signature or int(enclosure.get("length", "0")) != dmg.stat().st_size:
        raise RuntimeError("Archive signature or length is missing/incorrect")
    _, _, tag = version()
    expected_url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{dmg.name}"
    if enclosure.get("url") != expected_url:
        raise RuntimeError("Feed points outside the versioned release")
    run(str(TOOLS / "sign_update"), "--ed-key-file", "-", "--verify", str(dmg), signature, input=secret + "\n", text=True)


def publish():
    build, marketing, tag = version()
    if current_feed_version() >= int(build):
        print("Channel already contains this build or newer; nothing to replace")
        return
    secret = os.environ.pop("SPARKLE_PRIVATE_KEY")
    if len(base64.b64decode(secret, validate=True)) != 32:
        raise RuntimeError("Signing key must be an Ed25519 seed")
    archives = Path("build/updates")
    existing = release(tag)
    dmg = archives / f"WikiVibe-preview{build}.dmg"
    appcast = archives / "appcast.xml"
    checksum = dmg.with_suffix(".dmg.sha256")
    if existing is None:
        if not dmg.is_file():
            raise RuntimeError("Built DMG is missing")
        # No key file or Keychain entry: Sparkle reads the seed through stdin.
        run(str(TOOLS / "generate_appcast"), "--ed-key-file", "-", "--maximum-deltas", "0",
            "--maximum-versions", "1", "--download-url-prefix",
            f"https://github.com/{REPOSITORY}/releases/download/{tag}/", str(archives), input=secret + "\n", text=True)
        verify(appcast, dmg, build, secret)
        checksum.write_text(f"{hashlib.sha256(dmg.read_bytes()).hexdigest()}  {dmg.name}\n")
        notes = Path("build/update-notes.md")
        notes.write_text(f"WikiVibe {marketing}, build {build}.\n\n"
                         "Universal arm64/x86_64, macOS 15+. Signed Sparkle updates; choose Update in Settings. "
                         "Ad-hoc signed, not notarized. Existing builds without an updater need one manual installation.\n\n"
                         f"Commit: {os.environ['GITHUB_SHA']}\n\nSHA-256: `{checksum.read_text().split()[0]}`\n")
        # A draft hides incomplete uploads. Existing versioned assets are never replaced.
        run("gh", "release", "create", tag, str(dmg), str(checksum), str(appcast),
            "--repo", REPOSITORY, "--target", os.environ["GITHUB_SHA"], "--prerelease", "--draft",
            "--title", f"WikiVibe Preview {build}", "--notes-file", str(notes))
    else:
        # Resume a failed feed publication using the original assets, never a rebuild.
        for name in (dmg.name, checksum.name, appcast.name):
            download(tag, name, archives)
        verify(appcast, dmg, build, secret)
        if checksum.read_text().split()[0] != hashlib.sha256(dmg.read_bytes()).hexdigest():
            raise RuntimeError("Original release checksum does not match its archive")
    secret = None
    if existing is None or existing.get("draft"):
        run("gh", "release", "edit", tag, "--repo", REPOSITORY, "--draft=false")
    # Advance the feed only after all versioned assets are public.
    if release(FEED_TAG) is None:
        run("gh", "release", "create", FEED_TAG, str(appcast), "--repo", REPOSITORY,
            "--target", os.environ["GITHUB_SHA"], "--prerelease", "--title", "WikiVibe update channel",
            "--notes", "Signed Sparkle appcast. Updated only after a versioned release is available.")
    else:
        run("gh", "release", "upload", FEED_TAG, str(appcast), "--repo", REPOSITORY, "--clobber")


if __name__ == "__main__":
    {"plan": plan, "publish": publish}[sys.argv[1]]()
