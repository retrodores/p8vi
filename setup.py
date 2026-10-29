import os
import re
import subprocess
import sys
import shutil

# --- CONFIGURATION ---
TARGET_REPO = "https://github.com/gillham/prog8.git"
# Only used for snapshot builds, which are matched by commit on this branch.
# Release builds are matched by their version tag instead.
TARGET_BRANCH = "llvm"
# Compiler executable to match, e.g. "prog8c-beta" or "prog8c-llvm"
PROG8C = "prog8c-llvm"
REF_DIR = ".prog8-reference"
VERSION_FILE = "VERSION"
# Each upstream skill is linked here so Claude Code loads it automatically
SKILL_LINK_DIR = ".claude/skills"
# Marks a skill folder that was copied because symlinks weren't available
COPY_MARKER = ".copied-from-prog8-reference"

# Directories targeted for your agent context
TOP_LEVEL_FOLDERS = [
    ".agents/skills",
    "benchmark-c",
    "benchmark-program",
    "docs/source",
    "examples",
]

DEEP_FOLDERS = [
    "compiler/res/prog8lib",
    "parser/src/main/antlr",
    "compiler/test/arithmetic",
    "compiler/test/comparisons",
]

# Non-agent files to delete after downloading (relative to REF_DIR)
FILES_TO_SCRUB = [
    ".aiignore",
    ".editorconfig",
    ".gitignore",
    ".readthedocs.yaml",
    "AGENTS.md",
    "build.gradle.kts",
    "settings.gradle",
    "gradle.properties",
    "gradlew",
    "gradlew.bat",
    "Makefile",
    "linked-list-iteration-plan.md",
    "docs/source/conf.py",
    "docs/source/docutils.conf",
    "docs/source/prog8_lexer.py",
]

# Directories to delete after downloading (relative to REF_DIR)
FOLDERS_TO_SCRUB = [
    "docs/source/_static/css",
]

# Image/diagram files are deleted from these directories (relative to REF_DIR).
# Not from examples/, where some programs load their own binary assets.
IMAGE_DIRS = [
    "benchmark-c",
    "docs/source",
]
IMAGE_EXTENSIONS = (".png", ".jpg", ".gif", ".svg", ".odg")
# ---------------------


def run_command(cmd, cwd=None, capture=False):
    """Safely execute system commands and capture errors."""
    try:
        result = subprocess.run(
            cmd,
            check=True,
            cwd=cwd,
            stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        return result.stdout.decode().strip() if capture else None
    except subprocess.CalledProcessError as e:
        print(f"\n❌ Error executing: {' '.join(cmd)}")
        print(f"Details: {e.stderr.decode().strip()}")
        sys.exit(1)


def compiler_version():
    """Return (version, commit) for the installed PROG8C compiler.

    A release build prints only its version, e.g. "v12.3.4", and commit is None.
    A snapshot build (version contains a '-') also prints the commit it was
    built from.
    """
    # which() also finds .bat/.cmd wrappers on Windows, which subprocess won't
    prog8c = shutil.which(PROG8C)
    if not prog8c:
        print(f"\n❌ {PROG8C} was not found in PATH.")
        sys.exit(1)
    output = subprocess.run([prog8c, "-version"], capture_output=True, text=True).stdout

    version = re.search(r"Prog8 compiler (v\S+)", output)
    if not version:
        print(f"\n❌ Could not parse the {PROG8C} version from:\n{output}")
        sys.exit(1)
    commit = re.search(r"git commit ([0-9a-f]+)", output)
    if "-" in version.group(1) and commit:
        return version.group(1), commit.group(1)
    return version.group(1), None


def link_skills():
    """Link each upstream skill into SKILL_LINK_DIR, or copy it if needed.

    Windows only allows symlinks with Developer Mode or admin rights, so a
    failed symlink falls back to a copy.  Anything already there that we
    didn't create (not a symlink, no COPY_MARKER) is left alone.
    """
    skills_dir = os.path.join(REF_DIR, ".agents", "skills")
    os.makedirs(SKILL_LINK_DIR, exist_ok=True)
    for skill in sorted(os.listdir(skills_dir)):
        source = os.path.join(skills_dir, skill)
        if not os.path.isdir(source):
            continue
        link = os.path.join(SKILL_LINK_DIR, skill)
        if os.path.islink(link):
            os.remove(link)
        elif os.path.isdir(link):
            if not os.path.exists(os.path.join(link, COPY_MARKER)):
                print(f"⚠️  Skipping skill {skill}: {link} exists and isn't ours.")
                continue
            shutil.rmtree(link)
        try:
            os.symlink(os.path.relpath(source, SKILL_LINK_DIR), link)
            print(f"Linked skill {skill}")
        except OSError:
            shutil.copytree(source, link)
            open(os.path.join(link, COPY_MARKER), "w").close()
            print(f"Copied skill {skill} (symlinks not available)")


def main():
    print("🤖 Setting up filtered Prog8 agent reference files...")

    version, commit = compiler_version()
    print(f"Matching {PROG8C} {version}" + (f" (commit {commit})" if commit else ""))

    # 1. Clean up any existing target directory
    if os.path.exists(REF_DIR):
        print(f"Removing old local {REF_DIR} directory...")
        shutil.rmtree(REF_DIR)

    os.makedirs(REF_DIR)

    try:
        # 2. Initialize temporary Git repo for sparse pulling
        print("Initializing temporary download workspace...")
        run_command(["git", "init"], cwd=REF_DIR)
        run_command(["git", "remote", "add", "origin", TARGET_REPO], cwd=REF_DIR)

        # 3. Configure sparse-checkout paths
        run_command(["git", "config", "core.sparseCheckout", "true"], cwd=REF_DIR)

        sparse_file_path = os.path.join(REF_DIR, ".git", "info", "sparse-checkout")
        with open(sparse_file_path, "w", encoding="utf-8") as f:
            f.write("/*\n")
            f.write("!/*/\n")
            for folder in TOP_LEVEL_FOLDERS:
                f.write(f"/{folder}/\n")
            for folder in DEEP_FOLDERS:
                f.write(f"/{folder}/\n")

        # 4. Fetch the source matching the installed compiler
        print("Downloading target folders...")
        if commit:
            # Snapshot: the abbreviated commit can't be fetched directly, so
            # fetch the branch history (without blobs) and check out the commit.
            run_command(
                ["git", "fetch", "--filter=blob:none", "origin", TARGET_BRANCH],
                cwd=REF_DIR,
            )
            run_command(["git", "checkout", commit], cwd=REF_DIR)
        else:
            run_command(
                ["git", "fetch", "--depth=1", "origin", f"refs/tags/{version}"],
                cwd=REF_DIR,
            )
            run_command(["git", "checkout", "FETCH_HEAD"], cwd=REF_DIR)
        full_commit = run_command(["git", "rev-parse", "HEAD"], cwd=REF_DIR, capture=True)

        # 5. Scrub unwanted build/config files and images from the reference
        print("Scrubbing build files and images...")
        for filename in FILES_TO_SCRUB:
            file_path = os.path.join(REF_DIR, filename)
            if os.path.exists(file_path):
                os.remove(file_path)
        for folder in FOLDERS_TO_SCRUB:
            folder_path = os.path.join(REF_DIR, folder)
            if os.path.exists(folder_path):
                shutil.rmtree(folder_path)
        for image_dir in IMAGE_DIRS:
            for root, dirs, files in os.walk(os.path.join(REF_DIR, image_dir)):
                for file in files:
                    if file.lower().endswith(IMAGE_EXTENSIONS):
                        os.remove(os.path.join(root, file))

        # 6. Remove the nested .git folder entirely
        print("Finalizing file structure and removing nested Git tracking...")
        git_folder_path = os.path.join(REF_DIR, ".git")
        if os.path.exists(git_folder_path):
            # Windows workaround: remove read-only attributes before deleting if needed
            if os.name == "nt":
                for root, dirs, files in os.walk(git_folder_path):
                    for file in files:
                        os.chmod(os.path.join(root, file), 0o777)
            shutil.rmtree(git_folder_path)

        # 7. Record what was downloaded, since there is no .git to ask anymore
        with open(os.path.join(REF_DIR, VERSION_FILE), "w", encoding="utf-8") as f:
            f.write(f"{version}\n{full_commit}\n")

        # 8. Make the upstream skills visible to Claude Code
        link_skills()

        print(
            f"\n✅ Setup complete! Reference files for {version} are isolated in: /{REF_DIR}"
        )
        print(
            "This folder contains only explicit code, documentation, and agent skills."
        )

    except Exception as e:
        print(f"\n❌ An unexpected error occurred: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
