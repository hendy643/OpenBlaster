#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Release the most recent tag: build the packages, write the release notes and publish both on GitHub.
#
#   scripts/release.sh [--dry-run] [--draft] [--no-build] [--no-test] [--tag TAG] [--notes FILE] [--formats "tar deb ..."]
#
#   --dry-run     do everything except the pushes to GitHub (the tag, the release); prints what it would run
#   --draft       publish the release as a draft
#   --no-build    use the packages already in dist/ (they must be for this tag's version) instead of building
#   --no-test     skip flutter analyze and flutter test
#   --tag TAG     release this tag, not the most recent one (git describe)
#   --notes FILE  use this text as the release notes instead of the generated ones
#   --formats     what scripts/package.sh builds (default: tar deb rpm pacman)
#
# The tag must be checked out (HEAD), on origin/master, and match `version:` in app/pubspec.yaml; the tree must be clean.
# v1.2.3-rc.1 is a pre-release of 1.2.3. A tag that is not on GitHub yet is pushed; one that is there at another commit
# is an error (move it yourself, deliberately). A release that exists is updated: its notes, and its files replaced.
# Needs git, the gh CLI (logged in: gh auth login), flutter and what scripts/package.sh needs (fpm, rpmbuild, zstd).
set -euo pipefail
cd "$(dirname "$0")/.."

dry=0 draft=0 build=1 run_tests=1 tag= notes= formats="tar deb rpm pacman"
while (($#)); do
    case $1 in
    --dry-run) dry=1; shift ;;
    --draft) draft=1; shift ;;
    --no-build) build=0; shift ;;
    --no-test) run_tests=0; shift ;;
    --tag) tag=${2:?--tag needs a tag}; shift 2 ;;
    --notes) notes=${2:?--notes needs a file}; shift 2 ;;
    --formats) formats=${2:?--formats needs a list}; shift 2 ;;
    -h | --help) sed -n 3,18p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
done
die() { echo "release: $*" >&2; exit 1; }
# show what a push would do, or do it
publish() { if ((dry)); then echo "  [dry run] $*"; else "$@"; fi; }

for tool in git gh; do command -v "$tool" >/dev/null || die "$tool is not installed"; done
gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
[[ -z $notes || -f $notes ]] || die "no such notes file: $notes"

# ---- the tag
[[ -n $tag ]] || tag=$(git describe --tags --abbrev=0) || die "there is no tag to release"
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]] || die "$tag is not a version tag (v1.2.3 or v1.2.3-rc.1)"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "no tag $tag"
commit=$(git rev-list -n1 "$tag")
[[ $(git rev-parse HEAD) == "$commit" ]] ||
    die "$tag is at $(git rev-parse --short "$commit"), but HEAD is at $(git rev-parse --short HEAD): check the tag out (git checkout $tag)"
[[ -z $(git status --porcelain) ]] || die "the working tree is not clean"
git fetch --quiet origin master || die "cannot reach origin"
git merge-base --is-ancestor "$commit" origin/master || die "$tag is not on origin/master"
version=${tag#v}
base=${version%%-*}
pub=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' app/pubspec.yaml)
[[ $base == "$pub" ]] || die "the tag says $base but app/pubspec.yaml says $pub: set the version, commit it and move the tag"
prerelease=0
[[ $version == *-* ]] && prerelease=1
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
echo "releasing $tag ($(git rev-parse --short "$commit")) of $repo$( ((prerelease)) && echo ', a pre-release')"

# ---- check, build, checksum
if ((run_tests)); then
    (cd app && flutter pub get >/dev/null && flutter analyze && flutter test)
fi
if ((build)); then
    rm -rf dist && mkdir dist
    # shellcheck disable=SC2086  # the formats are a word list
    scripts/package.sh $formats
fi
shopt -s nullglob
# the packages are named for the version in the pubspec, so v1.2.3-rc.1 and v1.2.3 make the same files
files=(dist/*"$base"*)
((${#files[@]})) || die "dist/ has no packages for $base (run without --no-build)"
(cd dist && sha256sum -- "${files[@]#dist/}" >SHA256SUMS)
files+=(dist/SHA256SUMS)

# ---- the notes: what changed since the tag before this one, and the checksums
if [[ -n $notes ]]; then
    cp "$notes" dist/RELEASE_NOTES.md
else
    # a release is compared with the release before it; only a pre-release is compared with the tag before it
    exclude=(); ((prerelease)) || exclude=(--exclude '*-*')
    previous=$(git describe --tags --abbrev=0 "${exclude[@]}" "$tag^" 2>/dev/null || true)
    range=${previous:+$previous..}$tag
    {
        echo "## OpenBlaster $version"
        echo
        if [[ -n $previous ]]; then echo "Changes since $previous:"; else echo "Changes:"; fi
        echo
        git log --no-merges --reverse --format='- %s (%h)' "$range"
        echo
        echo "### Packages"
        echo
        for f in "${files[@]}"; do
            case $f in
            *.deb) echo "- \`${f#dist/}\`: Debian, Ubuntu (\`sudo apt install ./${f#dist/}\`)" ;;
            *.rpm) echo "- \`${f#dist/}\`: Fedora, openSUSE (\`sudo dnf install ./${f#dist/}\`)" ;;
            *.pkg.tar.zst) echo "- \`${f#dist/}\`: Arch (\`sudo pacman -U ${f#dist/}\`)" ;;
            *.tar.gz) echo "- \`${f#dist/}\`: any distribution (a \`/usr\` and \`/etc\` tree)" ;;
            esac
        done
        echo
        echo "SHA-256:"
        echo
        echo '```'
        cat dist/SHA256SUMS
        echo '```'
        [[ -z $previous ]] || { echo; echo "Full changelog: https://github.com/$repo/compare/$previous...$tag"; }
    } >dist/RELEASE_NOTES.md
fi
echo "--- release notes (dist/RELEASE_NOTES.md)"
cat dist/RELEASE_NOTES.md
echo "--- files"
ls -l "${files[@]}"

# ---- publish: the tag, then the release
remote=$(git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}" | awk 'END {print $1}')
if [[ -z $remote ]]; then
    publish git push origin "refs/tags/$tag"
elif [[ $remote != "$commit" ]]; then
    die "$tag is at $(git rev-parse --short "$remote") on GitHub but at $(git rev-parse --short "$commit") here: not moving a published tag"
fi

flags=(--title "OpenBlaster $tag" --notes-file dist/RELEASE_NOTES.md)
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    echo "the release $tag exists: updating it"
    publish gh release edit "$tag" --repo "$repo" "${flags[@]}" $( ((prerelease)) && echo --prerelease)
    publish gh release upload "$tag" --repo "$repo" --clobber "${files[@]}"
else
    publish gh release create "$tag" --repo "$repo" --verify-tag "${flags[@]}" \
        $( ((prerelease)) && echo --prerelease) $( ((draft)) && echo --draft) "${files[@]}"
fi
((dry)) && echo "dry run: nothing was pushed" || echo "released: https://github.com/$repo/releases/tag/$tag"
