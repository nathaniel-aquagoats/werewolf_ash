"""Read a hook payload on stdin and print requested dotted fields, one per line.

Shared by the hook scripts so each one does not re-implement JSON parsing.
Missing fields print as an empty line, so callers can rely on line order.
"""

import json
import sys


def get(data, dotted):
    value = data
    for key in dotted.split("."):
        if not isinstance(value, dict):
            return ""
        value = value.get(key)
        if value is None:
            return ""
    if not isinstance(value, str):
        return ""
    # Collapse newlines so every field stays exactly one output line.
    return " ".join(value.split("\n"))


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    for field in sys.argv[1:]:
        print(get(data, field))


if __name__ == "__main__":
    main()
