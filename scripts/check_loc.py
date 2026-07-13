from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
LOWER = 3000
UPPER = 4000


def main() -> int:
    files = sorted(ROOT.joinpath("src").rglob("*.vy"))
    physical = 0
    non_empty = 0

    for path in files:
        lines = path.read_text(encoding="utf-8").splitlines()
        physical += len(lines)
        non_empty += sum(1 for line in lines if line.strip())

    print(f"src physical LOC: {physical}")
    print(f"src non-empty LOC: {non_empty}")

    if physical < LOWER or physical > UPPER:
        print(f"src physical LOC must remain between {LOWER} and {UPPER}", file=sys.stderr)
        return 1
    if non_empty < LOWER or non_empty > UPPER:
        print(f"src non-empty LOC must remain between {LOWER} and {UPPER}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
