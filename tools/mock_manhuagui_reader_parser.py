import json
import re
import sys
from urllib.parse import quote


IMG_HOST = "https://eu2.hamreus.com"


def matching_brace(text, start):
    if start < 0 or start >= len(text) or text[start] != "{":
        return -1
    depth = 0
    in_string = False
    escaping = False
    quote_ch = ""
    for index in range(start, len(text)):
        ch = text[index]
        if in_string:
            if escaping:
                escaping = False
            elif ch == "\\":
                escaping = True
            elif ch == quote_ch:
                in_string = False
            continue
        if ch in ("'", '"'):
            in_string = True
            quote_ch = ch
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return index
    return -1


def normalize_loose_json_object(value):
    value = re.sub(r"([{,]\s*)([A-Za-z_$][A-Za-z0-9_$]*)(\s*:)", r'\1"\2"\3', value or "")
    return re.sub(r"(:\s*)([A-Za-z_$][A-Za-z0-9_$]*|[0-9]+[A-Za-z_$][A-Za-z0-9_$]*)(\s*[,}])", r'\1"\2"\3', value)


def looks_like_files(value):
    return isinstance(value, list) and value and all(isinstance(item, str) and looks_like_image_file(item) for item in value)


def looks_like_path(value):
    return isinstance(value, str) and "/" in value and re.fullmatch(r"[A-Za-z0-9._/-]+", value or "") is not None


def looks_like_image_file(value):
    return isinstance(value, str) and re.search(r"\.(?:jpe?g|png|webp|gif|bmp)(?:$|\?)", value, re.I) is not None


def canonical_img_data(value):
    try:
        root = json.loads(normalize_loose_json_object(value))
    except Exception:
        return {}
    files = root.get("files")
    path = root.get("path")
    sl = root.get("sl")
    for item in root.values():
        if files is None and looks_like_files(item):
            files = item
        elif not path and looks_like_path(item):
            path = item
        elif sl is None and isinstance(item, dict) and ("e" in item or "m" in item):
            sl = item
    if not path or not files:
        return {}
    return {"path": path, "files": files, "sl": sl or {}}


def extract_img_data(script):
    # First, direct known forms.
    for marker in ("SMH.imgData", 'SMH["imgData"]', "SMH['imgData']"):
        search = 0
        while True:
            index = script.find(marker, search)
            if index < 0:
                break
            open_paren = script.find("(", index + len(marker))
            start = script.find("{", open_paren)
            end = matching_brace(script, start)
            if end > start:
                data = canonical_img_data(script[start:end + 1])
                if data:
                    return data
            search = index + len(marker)
    # Then fallback: tokenized object inside any wrapper call.
    search = 0
    while True:
        start = script.find("{", search)
        if start < 0:
            return {}
        end = matching_brace(script, start)
        if end > start:
            data = canonical_img_data(script[start:end + 1])
            if data:
                return data
        search = start + 1


def image_urls(data):
    encoded_path = "/".join(quote(part) for part in data["path"].strip("/").split("/") if part)
    encoded_path = f"/{encoded_path}/" if encoded_path else "/"
    e = data.get("sl", {}).get("e", "")
    m = data.get("sl", {}).get("m", "")
    return [f"{IMG_HOST}{encoded_path}{file}?e={e}&m={m}" for file in data["files"]]


def referer_for_image(image_url, page_url, fallback="https://www.manhuagui.com/"):
    if any(host in image_url for host in ("manhuagui.com", "mhgui.com", "hamreus.com")):
        return page_url or fallback
    return fallback


def check(name, script, expected_first):
    data = extract_img_data(script)
    urls = image_urls(data) if data else []
    if not urls or urls[0] != expected_first:
        print(f"FAIL {name}")
        print("data=", data)
        print("urls=", urls)
        print("expected=", expected_first)
        return False
    print(f"PASS {name}: {urls[0]}")
    return True


def check_referer():
    image = "https://eu2.hamreus.com/ps3/a/001.jpg?e=x&m=y"
    chapter = "https://www.manhuagui.com/comic/38579/533684.html"
    actual = referer_for_image(image, chapter)
    if actual != chapter:
        print(f"FAIL image referer: {actual}")
        return False
    print(f"PASS image referer: {actual}")
    return True


def main():
    cases = [
        (
            "direct imgData",
            'SMH.imgData({"path":"/ps3/a/","files":["001.jpg"],"sl":{"e":"x","m":"y"}}).preInit();',
            "https://eu2.hamreus.com/ps3/a/001.jpg?e=x&m=y",
        ),
        (
            "bracket imgData",
            'SMH["imgData"]({path:"/ps3/b/",files:["002.jpg"],sl:{e:"x",m:"y"}}).preInit();',
            "https://eu2.hamreus.com/ps3/b/002.jpg?e=x&m=y",
        ),
        (
            "token wrapper object",
            '3f.1K({"1h":5,"1g":"5.1","1d":"meta","1c":1b,"1a":"19","18":["17.1.3","16.1.3"],"2a":{"e":"x","m":"y"}}).preInit();',
            "",
        ),
    ]
    ok = all(check(*case) if case[2] else not extract_img_data(case[1]) for case in cases) and check_referer()
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
