import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/local-install.yml"
INSTALLER = ROOT / "scripts/dev/install-fixed-build.sh"
POST_MERGE = ROOT / "scripts/hooks/post-merge"


def test_local_install_workflow_contract():
    text = WORKFLOW.read_text()
    assert "name: local-install" in text
    assert "branches: [main]" in text
    assert "workflow_dispatch:" in text
    assert "runs-on: [self-hosted, aidash-leemini]" in text
    assert "github.event.pull_request.head.repo.full_name == github.repository" in text
    assert "./scripts/dev/install-fixed-build.sh" in text


def test_fixed_installer_contract_and_syntax():
    text = INSTALLER.read_text()
    assert "xcodegen generate" in text
    assert 'SYMROOT="$TMP_DD/Build/Products"' in text
    assert 'CONFIGURATION_BUILD_DIR="$PRODUCTS"' in text
    assert 'open -g "$APP_DST"' in text
    subprocess.run(["bash", "-n", str(INSTALLER)], check=True)


def test_post_merge_hook_is_executable_and_valid():
    assert POST_MERGE.stat().st_mode & 0o111
    subprocess.run(["bash", "-n", str(POST_MERGE)], check=True)
