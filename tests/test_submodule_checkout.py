"""Regression checks for initial submodule checkout observations.

Run with: python3 tests/test_submodule_checkout.py
Requires Git, CMake, and local file-protocol submodule support.
"""
from pathlib import Path
import hashlib
import shutil
import subprocess
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / "cmake" / "SubmoduleCheckout.cmake"


def command(*args, check=True):
    result = subprocess.run(args, text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(f"{args}: {result.stdout}\n{result.stderr}")
    return result


def git(repo, *args):
    return command("git", "-C", str(repo), *args).stdout.strip()


def fixture(root):
    sub = root / "origin"
    sub.mkdir()
    command("git", "init", "-b", "main", str(sub))
    for key, value in (("user.name", "Fixture"), ("user.email", "fixture@example.org")):
        git(sub, "config", key, value)
    commits = []
    for letter in "ABC":
        (sub / "value").write_text(letter)
        git(sub, "add", "value")
        git(sub, "commit", "-m", letter)
        commits.append(git(sub, "rev-parse", "HEAD"))

    parent = root / "parent"
    parent.mkdir()
    command("git", "init", "-b", "main", str(parent))
    git(parent, "config", "user.name", "Fixture")
    git(parent, "config", "user.email", "fixture@example.org")
    git(parent, "-c", "protocol.file.allow=always", "submodule", "add", str(sub), "ss/dep")
    checkout = parent / "ss" / "dep"
    git(checkout, "checkout", commits[0])
    git(parent, "add", ".")
    git(parent, "commit", "-m", "pin A")
    first_parent = git(parent, "rev-parse", "HEAD")
    git(checkout, "checkout", commits[1])
    git(parent, "add", "ss/dep")
    git(parent, "commit", "-m", "pin B")
    git(checkout, "checkout", commits[0])
    return parent, checkout, commits, first_parent


def configure(root, parent, preserve=False):
    client = root / "client"
    client.mkdir(exist_ok=True)
    (client / "CMakeLists.txt").write_text(
        'cmake_minimum_required(VERSION 3.15)\n'
        'project(Observe NONE)\n'
        'find_package(Git REQUIRED)\n'
        'function(get_gitlink_commit REPOSITORY SUBMODULE_PATH OUTPUT)\n'
        '  execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}" '
        'ls-files --stage -- "${SUBMODULE_PATH}" OUTPUT_VARIABLE entry)\n'
        '  if(NOT entry MATCHES "^160000 ([0-9a-fA-F]+) 0[\\t ]")\n'
        '    message(FATAL_ERROR "Bad staged Gitlink: ${entry}")\n'
        '  endif()\n'
        '  set(${OUTPUT} "${CMAKE_MATCH_1}" PARENT_SCOPE)\n'
        'endfunction()\n'
        f'include("{SCRIPT.as_posix()}")\n'
        f'_ariadne_checkout_submodule("{parent.as_posix()}" "ss/dep" actual)\n'
    )
    args = ["cmake", "-S", str(client), "-B", str(root / "build")]
    if preserve:
        args.append("-DARIADNE_PRESERVE_INITIAL_SUBMODULE_CHECKOUTS=ON")
    return command(*args, check=False)


def state(parent):
    git_dir = Path(git(parent, "rev-parse", "--absolute-git-dir"))
    key = hashlib.sha256(b"ss/dep").hexdigest()
    return git_dir / "ariadne" / "observed-gitlinks" / (key + ".txt")


def scenario(name, check):
    with tempfile.TemporaryDirectory(prefix="ariadne-checkout-") as tmp:
        root = Path(tmp)
        parent, checkout, commits, initial_parent = fixture(root)
        check(root, parent, checkout, commits, initial_parent)
    print("PASS", name)


def first_after_pull(root, parent, checkout, commits, first_parent):
    result = configure(root, parent)
    assert result.returncode == 0, result.stderr
    assert git(checkout, "rev-parse", "HEAD") == commits[1]
    assert state(parent).read_text().strip() == commits[1]
    git(parent, "checkout", first_parent)
    result = configure(root, parent)
    assert result.returncode == 0, result.stderr
    assert git(checkout, "rev-parse", "HEAD") == commits[0]


def unknown_override(root, parent, checkout, commits, first_parent):
    git(checkout, "checkout", commits[2])
    result = configure(root, parent)
    assert result.returncode == 0, result.stderr
    assert git(checkout, "rev-parse", "HEAD") == commits[2]
    assert not state(parent).exists()


def explicit_override(root, parent, checkout, commits, first_parent):
    result = configure(root, parent, preserve=True)
    assert result.returncode == 0, result.stderr
    assert git(checkout, "rev-parse", "HEAD") == commits[0]
    assert state(parent).read_text().strip() == commits[1]


def dirty(root, parent, checkout, commits, first_parent):
    (checkout / "value").write_text("dirty")
    result = configure(root, parent)
    assert result.returncode != 0
    assert "local changes" in result.stdout + result.stderr
    assert git(checkout, "rev-parse", "HEAD") == commits[0]
    assert not state(parent).exists()


def no_reflog(root, parent, checkout, commits, first_parent):
    git_dir = Path(git(parent, "rev-parse", "--absolute-git-dir"))
    (git_dir / "logs" / "HEAD").unlink()
    (git_dir / "logs" / "refs" / "heads" / "main").unlink()
    result = configure(root, parent)
    assert result.returncode == 0, result.stderr
    assert git(checkout, "rev-parse", "HEAD") == commits[0]
    assert not state(parent).exists()


def staged_override(root, parent, checkout, commits, first_parent):
    git(checkout, "checkout", commits[2])
    git(parent, "add", "ss/dep")
    git(checkout, "checkout", commits[0])
    result = configure(root, parent)
    assert result.returncode == 0, result.stderr
    assert git(checkout, "rev-parse", "HEAD") == commits[0]
    assert not state(parent).exists()


def aligned_then_override(root, parent, checkout, commits, first_parent):
    git(checkout, "checkout", commits[1])
    result = configure(root, parent)
    assert result.returncode == 0, result.stderr
    git(checkout, "checkout", commits[0])
    result = configure(root, parent)
    assert result.returncode == 0, result.stderr
    assert git(checkout, "rev-parse", "HEAD") == commits[0]
    assert state(parent).read_text().strip() == commits[1]


if __name__ == "__main__":
    for label, callback in (
        ("first_after_pull", first_after_pull),
        ("unknown_override", unknown_override),
        ("explicit_override", explicit_override),
        ("dirty_checkout", dirty),
        ("missing_reflog", no_reflog),
        ("staged_gitlink", staged_override),
        ("aligned_then_override", aligned_then_override),
    ):
        scenario(label, callback)
