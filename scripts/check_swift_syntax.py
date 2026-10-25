"""Optional Swift grammar check. Parsing does not type-check Apple APIs."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "outputs/validation-tools"))
try:
    import tree_sitter
    import tree_sitter_swift
except ImportError:
    raise SystemExit("Install optional parser into outputs/validation-tools, or use Xcode on a Mac.")

parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
files = sorted((ROOT / "SlowRun").rglob("*.swift")) + sorted((ROOT / "RunCore").rglob("*.swift"))
errors = []
for file in files:
    tree = parser.parse(file.read_bytes())
    def walk(node):
        if node.type == "ERROR" or node.is_missing:
            errors.append(f"{file.relative_to(ROOT)}:{node.start_point.row + 1}:{node.start_point.column + 1}: {node.type}")
        for child in node.children:
            walk(child)
    walk(tree.root_node)
if errors:
    print("\n".join(errors))
    raise SystemExit(1)
print(f"PASS: {len(files)} Swift files parsed without grammar errors.")
print("This is NOT Swift type-checking, XCTest, an Xcode build, or device verification.")
