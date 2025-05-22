from concurrent.futures import Future, ThreadPoolExecutor
import urllib.request
from typing import (
    Any,
    cast,
)
import json
import re


URL = "https://api.github.com/repos/astral-sh/uv/releases/latest"


# Match an uv binary asset
uv_re = re.compile(r"uv-(.+)\.tar\..+")


def match_uv(filename: str) -> re.Match[str] | None:
    m = uv_re.match(filename)
    if m:
        if filename.endswith(".sha256"):
            return None
        return m
    return None


if __name__ == "__main__":
    with urllib.request.urlopen(URL) as resp:
        release: dict[str, Any] = json.loads(resp.read())

    tag_name: str = release["tag_name"]
    assets: list[dict[str, Any]] = release["assets"]

    # Group assets by filename so we can extract the correct .sha256 suffixes
    files = {cast(str, asset["name"]): asset for asset in assets}

    # Output platform -> checksum
    checksums: dict[str, str] = {}

    def fetch_hash(platform: str, sha256_url: str):
        with urllib.request.urlopen(sha256_url) as resp:
            data: bytes = resp.read()
            checksums[platform] = data.split()[0].decode()

    # For each uv binary platform, download the hash file
    with ThreadPoolExecutor() as executor:
        futures: list[Future[None]] = []

        for filename in files:
            m = match_uv(filename)
            if not m:
                continue

            platform = m.group(1)
            sha256_url: str = files[f"{filename}.sha256"]["browser_download_url"]
            futures.append(executor.submit(fetch_hash, platform, sha256_url))

        for future in futures:
            future.result()

    with open("srcs.json", "w") as out:
        json.dump(
            {
                "version": tag_name,
                "platforms": {k: checksums[k] for k in sorted(checksums.keys())},
            },
            out,
            indent=2,
        )
        out.write("\n")
