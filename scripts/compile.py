from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    contracts = sorted(ROOT.joinpath("src").rglob("*.vy"))
    if not contracts:
        print("no Vyper contracts found", file=sys.stderr)
        return 1

    for contract in contracts:
        rel = contract.relative_to(ROOT)
        print(f"compiling {rel}")
        output_format = "abi" if contract.name == "PyxisCreditProtocol.vy" else "bytecode_runtime"
        subprocess.run(
            [sys.executable, "-m", "vyper", "-f", output_format, str(contract)],
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            check=True,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
