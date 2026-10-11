"""Read components from a retained XCTest hierarchy, without UI IPC per node.

The original hierarchy remains inside the xcresult-exported JSON with its hash.
This parser is a comparison aid, not a proof that a scene or test passed. Unknown
formats are rejected rather than turned into an empty successful comparison.
"""
import re


VISIBLE_TYPES = {"Button", "StaticText", "Image", "Switch", "SearchField", "TextField", "SecureTextField"}
NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
FRAME = re.compile(r"\{\{\s*(" + NUMBER + r"),\s*(" + NUMBER + r")\s*\},\s*\{\s*(" + NUMBER + r"),\s*(" + NUMBER + r")\s*\}\}")
FIELD = re.compile(r"\b(identifier|label|value):\s*('(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\")(?=,\s|$)")


def text_field(token):
    value = token[1:-1]
    return re.sub(r"\\([\\'\"nrt])", lambda m: {"n": "\n", "r": "\r", "t": "\t"}.get(m[1], m[1]), value)


def components_from_provenance(record):
    if record.get("componentCollection") is None:
        components = record.get("components")
        if not isinstance(components, list) or not components:
            raise ValueError("No actual Apple components in legacy provenance")
        return components
    if record.get("componentCollection") != "xcui-debug-description-v1":
        raise ValueError("Unknown Apple component collection format")
    snapshot = record.get("accessibilitySnapshot", "")
    if "Element subtree:" not in snapshot:
        raise ValueError("Retained XCTest hierarchy has no Element subtree")
    subtree = snapshot.split("Element subtree:", 1)[1].split("Path to element:", 1)[0]
    window = record["appFrame"]
    left, top = float(window["x"]), float(window["y"])
    right, bottom = left + float(window["width"]), top + float(window["height"])
    components = []
    for line in subtree.splitlines():
        node = re.match(r"\s*([A-Za-z]+),", line)
        if not node or node[1] not in VISIBLE_TYPES:
            continue
        rectangle = FRAME.search(line)
        if not rectangle:
            raise ValueError("Apple component frame cannot be parsed: " + node[1])
        x, y, width, height = (float(v) for v in rectangle.groups())
        if width <= 0 or height <= 0 or x >= right or y >= bottom or x + width <= left or y + height <= top:
            continue
        fields = {match[1]: text_field(match[2]) for match in FIELD.finditer(line)}
        if "label:" in line and "label" not in fields:
            raise ValueError("Apple component label cannot be parsed: " + node[1])
        components.append({"type": node[1], "label": fields.get("label", ""),
                           "identifier": fields.get("identifier", ""), "value": fields.get("value", ""),
                           "bounds": [x, y, x + width, y + height],
                           "origin": "retained-xcui-debug-description"})
    if not components:
        raise ValueError("No visible Apple components could be read from the retained hierarchy")
    return components
