#!/usr/bin/env python3
"""Read the designated iOS CI using the account's normal Git credentials.

Credentials stay in memory. Redirected artifact requests receive no authorization
header. This tool never uploads files, dispatches jobs, or changes authentication.
"""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


REPOSITORY = "sermisellek2-spec/xx-comic-ios"
ACCOUNT = "sermisellek2-spec"
BRANCH = "codex/ios-port"
ROOT = Path(__file__).resolve().parent.parent
API_ROOT = "https://api.github.com"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


class CIError(Exception):
    pass


class GitHubCI:
    def __init__(self):
        environment = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="never")
        credential = subprocess.run(
            ["git", "credential", "fill"],
            input=f"protocol=https\nhost=github.com\nusername={ACCOUNT}\n\n",
            cwd=ROOT, env=environment, text=True, capture_output=True,
        )
        if credential.returncode:
            raise CIError("本机正常 GitHub 凭据不可用；未打印凭据助手输出。")
        fields = dict(line.split("=", 1) for line in credential.stdout.splitlines() if "=" in line)
        if not fields.get("password"):
            raise CIError("凭据助手没有返回可用的认证。")
        self.headers = {
            "Authorization": "Bearer " + fields["password"],
            "Accept": "application/vnd.github+json",
            "User-Agent": "xxcomic-ios-validation",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, path):
        if not (path == "/user" or path.startswith(f"/repos/{REPOSITORY}")):
            raise CIError("请求不属于指定 iOS 仓库。")
        request = urllib.request.Request(API_ROOT + path, headers=self.headers)
        try:
            return self.opener.open(request, timeout=45)
        except urllib.error.HTTPError as error:
            if error.code in (301, 302, 303, 307, 308):
                location = error.headers.get("Location")
                error.close()
                if not location or urllib.parse.urlsplit(location).scheme != "https":
                    raise CIError("产物下载地址没有使用 HTTPS。")
                # Signed download URLs are intentionally not included in output.
                return urllib.request.urlopen(location, timeout=60)
            status = error.code
            error.close()
            raise CIError(f"GitHub API 返回 HTTP {status}。") from None
        except urllib.error.URLError:
            raise CIError("无法连接指定仓库的 GitHub API。") from None

    def json(self, path):
        with self.request(path) as response:
            return json.load(response)

    def download(self, path, output):
        target = local_path(output)
        target.parent.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha256()
        size = 0
        with self.request(path) as response, target.open("xb") as stream:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > 1024 * 1024 * 1024:
                    raise CIError("CI 产物超过本次允许的 1GiB 下载大小。")
                digest.update(chunk)
                stream.write(chunk)
        return {"path": target.relative_to(ROOT).as_posix(), "bytes": size, "sha256": digest.hexdigest()}


def local_path(value):
    result = (ROOT / value).resolve()
    if not result.is_relative_to(ROOT):
        raise CIError("输出位置必须在当前 iOS 工作区中。")
    return result


def run_summary(run):
    fields = ("id", "html_url", "status", "conclusion", "head_sha", "head_branch", "event", "run_attempt", "created_at", "updated_at")
    return {key: run.get(key) for key in fields}


def main():
    parser = argparse.ArgumentParser(description="读取唯一指定的 iOS CI，不输出认证信息。")
    parser.add_argument("--json-output", help="在工作区中保存过滤后的 JSON 证据")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("auth")
    runs = commands.add_parser("runs")
    runs.add_argument("--sha", required=True)
    runs.add_argument("--ref", default=BRANCH, help="本次CI的实际分支；默认codex/ios-port")
    run = commands.add_parser("run")
    run.add_argument("id", type=int)
    artifacts = commands.add_parser("artifacts")
    artifacts.add_argument("id", type=int)
    for name in ("logs", "download"):
        command = commands.add_parser(name)
        command.add_argument("id", type=int)
        command.add_argument("output")
    args = parser.parse_args()
    api = GitHubCI()
    prefix = f"/repos/{REPOSITORY}"
    if args.command == "auth":
        user = api.json("/user")
        repo = api.json(prefix)
        if user["login"].lower() != ACCOUNT or repo["full_name"].lower() != REPOSITORY:
            raise CIError("登录账号或仓库与指定目标不一致。")
        branch = api.json(prefix + "/branches/" + urllib.parse.quote(BRANCH, safe=""))
        result = {
            "authenticated": True, "login": user["login"], "repository": repo["full_name"],
            "private": repo["private"], "permissions": repo.get("permissions", {}),
            "branch": BRANCH, "branch_head": branch["commit"]["sha"],
            "credential_source": "normal Git Credential Manager; credentials kept in process memory",
        }
    elif args.command == "runs":
        query = urllib.parse.urlencode({"branch": args.ref, "head_sha": args.sha, "per_page": 30})
        result = {"runs": [run_summary(run) for run in api.json(prefix + "/actions/runs?" + query)["workflow_runs"] if run["head_sha"] == args.sha]}
    elif args.command == "run":
        result = run_summary(api.json(prefix + f"/actions/runs/{args.id}"))
        jobs = api.json(prefix + f"/actions/runs/{args.id}/jobs?per_page=100")["jobs"]
        result["jobs"] = [{
            "id": job["id"], "name": job["name"], "status": job["status"], "conclusion": job["conclusion"],
            "steps": [{key: step.get(key) for key in ("name", "status", "conclusion", "number", "started_at", "completed_at")} for step in job.get("steps", [])],
        } for job in jobs]
    elif args.command == "artifacts":
        result = {"artifacts": [{key: artifact.get(key) for key in ("id", "name", "size_in_bytes", "expired", "created_at")} for artifact in api.json(prefix + f"/actions/runs/{args.id}/artifacts?per_page=100")["artifacts"]]}
    else:
        path = prefix + (f"/actions/runs/{args.id}/logs" if args.command == "logs" else f"/actions/artifacts/{args.id}/zip")
        result = api.download(path, args.output)
    result["checked_at_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    if args.json_output:
        output = local_path(args.json_output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    try:
        main()
    except (CIError, FileExistsError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        raise SystemExit(1)
